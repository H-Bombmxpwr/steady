import Foundation
import SwiftData

/// Pulls planned workouts out of TrainingPeaks through the private iCalendar
/// feed every athlete account can publish (TrainingPeaks → Account Settings →
/// Calendar Sync). No OAuth, no partner approval, no credentials stored — just
/// a URL the athlete controls and can revoke.
///
/// What crosses the network: an HTTPS GET to trainingpeaks.com for the feed.
/// Nothing from this app is uploaded, and the parsed sessions land in the same
/// on-device store as everything else.
enum TrainingPeaksSync {

    /// How much of the calendar to keep. Far enough back to still see the week
    /// just gone, far enough forward to plan a training block.
    static let pastDays = 30
    static let futureDays = 120

    struct Result {
        let added: Int
        let updated: Int
        let removed: Int

        var isEmpty: Bool { added == 0 && updated == 0 && removed == 0 }

        var summary: String {
            if isEmpty { return "Already up to date." }
            var parts: [String] = []
            if added > 0 { parts.append("\(added) added") }
            if updated > 0 { parts.append("\(updated) updated") }
            if removed > 0 { parts.append("\(removed) removed") }
            return parts.joined(separator: " · ")
        }
    }

    enum SyncError: LocalizedError {
        case badURL
        case network(String)
        case notCalendar

        var errorDescription: String? {
            switch self {
            case .badURL:
                return "That doesn't look like a calendar URL. Copy the whole link from TrainingPeaks → Account Settings → Calendar Sync."
            case .network(let detail):
                return "Couldn't reach TrainingPeaks: \(detail)"
            case .notCalendar:
                return "That link didn't return a calendar. Make sure you copied the iCal / calendar-sync URL, not the TrainingPeaks website address."
            }
        }
    }

    /// TrainingPeaks hands out `webcal://` links, which URLSession won't load.
    /// Same server, different scheme.
    static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.lowercased().hasPrefix("webcal://") {
            text = "https://" + text.dropFirst("webcal://".count)
        }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host != nil else { return nil }
        return url
    }

    @discardableResult
    static func sync(plan: Plan) async throws -> Result {
        guard let url = normalize(plan.trainingPeaksFeedURL ?? "") else { throw SyncError.badURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("text/calendar", forHTTPHeaderField: "Accept")

        let data: Data
        do {
            let (body, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw SyncError.network("the server said \(http.statusCode).")
            }
            data = body
        } catch let error as SyncError {
            throw error
        } catch {
            throw SyncError.network(error.localizedDescription)
        }

        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              text.contains("BEGIN:VCALENDAR") else { throw SyncError.notCalendar }

        let result = apply(ICSParser.parse(text), to: plan)
        plan.trainingPeaksLastSync = Date()
        return result
    }

    /// Import from a downloaded `.ics` file — the offline path, and the
    /// fallback when a feed URL isn't available.
    @discardableResult
    static func importFile(at url: URL, into plan: Plan) throws -> Result {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              text.contains("BEGIN:VCALENDAR") else { throw SyncError.notCalendar }
        return apply(ICSParser.parse(text), to: plan)
    }

    // MARK: - Applying a feed

    /// Reconcile the feed against what's stored: add new sessions, update
    /// moved or edited ones in place, and drop imported sessions the feed no
    /// longer lists — a coach deleting Thursday has to actually delete
    /// Thursday, or the budget keeps paying for a session that isn't happening.
    ///
    /// Only sessions this integration created are ever removed; anything
    /// entered by hand is left alone.
    static func apply(_ events: [ICSEvent], to plan: Plan) -> Result {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let windowStart = cal.date(byAdding: .day, value: -pastDays, to: today),
              let windowEnd = cal.date(byAdding: .day, value: futureDays, to: today)
        else { return Result(added: 0, updated: 0, removed: 0) }

        let inWindow = events.filter { $0.start >= windowStart && $0.start <= windowEnd }
        let feedIDs = Set(inWindow.map(\.uid))

        var existing: [String: PlannedWorkout] = [:]
        for workout in plan.plannedWorkouts where workout.isImported {
            if let id = workout.externalID { existing[id] = workout }
        }

        var added = 0
        var updated = 0

        for event in inWindow {
            guard let parsed = interpret(event) else { continue }

            if let match = existing[event.uid] {
                let changed = match.date != parsed.date
                    || match.name != parsed.name
                    || match.minutes != parsed.minutes
                    || match.categoryRaw != parsed.category.rawValue
                    || match.intensityRaw != parsed.intensity.rawValue
                    || match.hour != parsed.hour
                    || match.minute != parsed.minute
                if changed {
                    match.date = parsed.date
                    match.name = parsed.name
                    match.minutes = parsed.minutes
                    match.hour = parsed.hour
                    match.minute = parsed.minute
                    match.category = parsed.category
                    match.intensity = parsed.intensity
                    match.details = parsed.details
                    match.tss = parsed.tss
                    match.distanceMiles = parsed.distanceMiles
                    updated += 1
                }
            } else {
                plan.plannedWorkouts.append(
                    PlannedWorkout(date: parsed.date,
                                   name: parsed.name,
                                   minutes: parsed.minutes,
                                   hour: parsed.hour,
                                   minute: parsed.minute,
                                   category: parsed.category,
                                   intensity: parsed.intensity,
                                   details: parsed.details,
                                   source: "trainingpeaks",
                                   externalID: event.uid,
                                   tss: parsed.tss,
                                   distanceMiles: parsed.distanceMiles))
                added += 1
            }
        }

        // Anything imported, inside the window, and no longer in the feed.
        let stale = plan.plannedWorkouts.filter {
            $0.isImported
                && $0.date >= windowStart && $0.date <= windowEnd
                && !feedIDs.contains($0.externalID ?? "")
        }
        let staleIDs = Set(stale.map(\.persistentModelID))
        if !staleIDs.isEmpty {
            plan.plannedWorkouts.removeAll { staleIDs.contains($0.persistentModelID) }
            stale.forEach { $0.modelContext?.delete($0) }
        }

        return Result(added: added, updated: updated, removed: stale.count)
    }

    // MARK: - Interpreting one event

    struct ParsedWorkout {
        let date: Date
        let name: String
        let minutes: Int
        let hour: Int
        let minute: Int
        let category: WorkoutCategory
        let intensity: WorkoutIntensity
        let details: String?
        let tss: Double?
        let distanceMiles: Double?
    }

    /// Turn a calendar event into a session. Rest days and non-workout events
    /// return nil so they don't clutter the plan or add phantom calories.
    static func interpret(_ event: ICSEvent) -> ParsedWorkout? {
        let text = ([event.summary, event.description ?? ""]).joined(separator: "\n")
        let lower = text.lowercased()

        // TrainingPeaks publishes notes, metrics, and day-off markers into the
        // same calendar as the sessions.
        if lower.contains("rest day") || lower.hasPrefix("day off") { return nil }

        let planned = duration(in: text)
        let minutes = planned ?? event.minutes ?? 60
        guard minutes >= 5 else { return nil }

        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: event.start)

        let tssValue = number(in: text, labels: ["planned tss", "tss"])
        let distance = number(in: text, labels: ["planned distance", "distance"])

        return ParsedWorkout(
            date: cal.startOfDay(for: event.start),
            name: cleanName(event.summary),
            minutes: minutes,
            // All-day entries have no meaningful time; 7 am is a better
            // default than midnight for a reminder and a fueling window.
            hour: event.isAllDay ? 7 : (comps.hour ?? 7),
            minute: event.isAllDay ? 0 : (comps.minute ?? 0),
            category: category(for: lower),
            intensity: intensity(text: lower, tss: tssValue, minutes: minutes),
            details: event.description,
            tss: tssValue,
            distanceMiles: distance)
    }

    /// Strip the noise TrainingPeaks prefixes onto event titles so the card
    /// shows the workout's name, not its metadata.
    static func cleanName(_ summary: String) -> String {
        var name = summary
        for prefix in ["Planned:", "Workout:", "TP:"] {
            if name.lowercased().hasPrefix(prefix.lowercased()) {
                name = String(name.dropFirst(prefix.count))
            }
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Workout" : name
    }

    /// Find a planned duration. Handles "Duration: 1:30", "1h 45m", "90 min".
    static func duration(in text: String) -> Int? {
        // "Duration: 1:30" / "Planned Duration: 01:30:00"
        if let match = text.firstMatch(
            of: /(?i)(?:planned\s+)?duration\s*[:\-]?\s*(\d{1,2}):(\d{2})(?::(\d{2}))?/) {
            let hours = Int(match.1) ?? 0
            let mins = Int(match.2) ?? 0
            return hours * 60 + mins
        }
        // "1h 30m" / "1 hr 30 min"
        if let match = text.firstMatch(of: /(?i)(\d{1,2})\s*(?:h|hr|hour)s?\s*(\d{1,2})?\s*(?:m|min)?/) {
            let hours = Int(match.1) ?? 0
            let mins = match.2.flatMap { Int($0) } ?? 0
            let total = hours * 60 + mins
            if total >= 5 { return total }
        }
        // "90 min"
        if let match = text.firstMatch(of: /(?i)(\d{2,3})\s*(?:min|minutes)\b/) {
            return Int(match.1)
        }
        return nil
    }

    /// Pull a labelled number ("TSS: 85", "Distance: 20.5 mi") out of the text.
    static func number(in text: String, labels: [String]) -> Double? {
        for label in labels {
            let pattern = try? Regex("(?i)\(NSRegularExpression.escapedPattern(for: label))\\s*[:\\-]?\\s*([0-9]+(?:\\.[0-9]+)?)")
            if let pattern, let match = text.firstMatch(of: pattern),
               let range = match.output[1].range,
               let value = Double(text[range]) {
                return value
            }
        }
        return nil
    }

    /// Map the sport in the title onto the app's coarse workout categories —
    /// which is all the fueling engine needs, since it cares about glycogen
    /// demand rather than the specific sport.
    static func category(for lower: String) -> WorkoutCategory {
        let endurance = ["bike", "cycl", "ride", "run", "jog", "swim", "row",
                         "brick", "triathlon", "duathlon", "walk", "hike",
                         "ski", "elliptical", "cardio", "mtb", "gravel", "trainer"]
        let strength = ["strength", "gym", "weight", "lift", "squat", "deadlift",
                        "bench", "core", "resistance", "crossfit"]
        let mobility = ["yoga", "stretch", "mobility", "foam", "recovery ride",
                        "pilates", "rehab", "physio"]
        let sports = ["soccer", "football", "basketball", "tennis", "hockey",
                      "climb", "surf", "golf", "match", "game", "practice"]

        if mobility.contains(where: lower.contains) { return .mobility }
        if strength.contains(where: lower.contains) { return .strength }
        if sports.contains(where: lower.contains) { return .sports }
        if endurance.contains(where: lower.contains) { return .cardio }
        return .other
    }

    /// How hard the session is meant to be.
    ///
    /// TSS is the honest signal when the plan published one: 100 TSS is an
    /// hour at threshold by definition, so TSS per hour recovers roughly the
    /// intensity factor. Failing that, coaches name their sessions in a
    /// remarkably consistent vocabulary.
    static func intensity(text lower: String, tss: Double?, minutes: Int) -> WorkoutIntensity {
        if let tss, tss > 0, minutes > 0 {
            let perHour = tss / (Double(minutes) / 60.0)
            switch perHour {
            case ..<55:  return .easy
            case ..<80:  return .moderate
            default:     return .hard
            }
        }

        let hard = ["interval", "vo2", "threshold", "race", "max", "anaerobic",
                    "sprint", "hard", "hiit", "test", "ftp", "tt ", "time trial",
                    "hill repeat", "sweet spot"]
        let easy = ["recovery", "easy", "z1", "z2", "zone 1", "zone 2", "shakeout",
                    "spin", "active recovery", "openers", "aerobic base"]

        if hard.contains(where: lower.contains) { return .hard }
        if easy.contains(where: lower.contains) { return .easy }
        return .moderate
    }
}
