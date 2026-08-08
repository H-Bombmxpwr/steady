import Foundation

/// One VEVENT, reduced to the fields a training plan actually carries.
struct ICSEvent {
    let uid: String
    let summary: String
    let description: String?
    let start: Date
    let end: Date?
    /// True for all-day events (`VALUE=DATE`), which is how TrainingPeaks
    /// publishes a workout with no scheduled time.
    let isAllDay: Bool

    var minutes: Int? {
        guard let end, end > start, !isAllDay else { return nil }
        return Int(end.timeIntervalSince(start) / 60)
    }
}

/// A small, forgiving iCalendar reader — enough of RFC 5545 to read a
/// published calendar feed, and no more. Full-fat parsers exist, but a
/// training feed is a flat list of VEVENTs with no recurrence, no alarms, and
/// no timezone definitions worth honoring beyond the offsets in the stamps.
enum ICSParser {

    static func parse(_ text: String) -> [ICSEvent] {
        var events: [ICSEvent] = []
        var current: [String: (value: String, params: [String: String])] = [:]
        var inEvent = false

        for line in unfold(text) {
            if line == "BEGIN:VEVENT" {
                inEvent = true
                current = [:]
                continue
            }
            if line == "END:VEVENT" {
                inEvent = false
                if let event = makeEvent(from: current) { events.append(event) }
                current = [:]
                continue
            }
            guard inEvent else { continue }

            // "DTSTART;TZID=America/Denver:20260807T070000"
            guard let colon = line.firstIndex(of: ":") else { continue }
            let rawName = String(line[line.startIndex..<colon])
            let value = String(line[line.index(after: colon)...])

            let nameParts = rawName.split(separator: ";").map(String.init)
            guard let name = nameParts.first?.uppercased() else { continue }
            var params: [String: String] = [:]
            for part in nameParts.dropFirst() {
                let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { params[kv[0].uppercased()] = kv[1] }
            }
            current[name] = (value, params)
        }
        return events
    }

    /// RFC 5545 line folding: a line beginning with a space or tab is a
    /// continuation of the one before it, with the leading whitespace dropped.
    private static func unfold(_ text: String) -> [String] {
        var out: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if let first = line.first, first == " " || first == "\t" {
                if !out.isEmpty { out[out.count - 1] += String(line.dropFirst()) }
            } else if !line.isEmpty {
                out.append(line)
            }
        }
        return out
    }

    private static func makeEvent(
        from fields: [String: (value: String, params: [String: String])]
    ) -> ICSEvent? {
        guard let startField = fields["DTSTART"],
              let start = date(from: startField.value, params: startField.params)
        else { return nil }

        let isAllDay = startField.params["VALUE"]?.uppercased() == "DATE"
            || startField.value.count == 8

        let end = fields["DTEND"].flatMap { date(from: $0.value, params: $0.params) }
        let summary = fields["SUMMARY"].map { unescape($0.value) } ?? "Workout"
        let description = fields["DESCRIPTION"].map { unescape($0.value) }
        // A feed without UIDs is malformed, but rather than drop the event we
        // synthesize a stable key so re-syncs still dedupe.
        let uid = fields["UID"]?.value ?? "\(summary)-\(start.timeIntervalSince1970)"

        return ICSEvent(uid: uid, summary: summary, description: description,
                        start: start, end: end, isAllDay: isAllDay)
    }

    /// Handles the three stamp shapes that show up in practice: a bare date,
    /// a floating/zoned local time, and a UTC time with a trailing Z.
    static func date(from value: String, params: [String: String] = [:]) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        if trimmed.count == 8 {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd"
            f.timeZone = TimeZone.current
            return f.date(from: trimmed)
        }

        let isUTC = trimmed.hasSuffix("Z")
        let zone: TimeZone
        if isUTC {
            zone = TimeZone(identifier: "UTC") ?? .current
        } else if let tzid = params["TZID"], let tz = TimeZone(identifier: tzid) {
            zone = tz
        } else {
            zone = .current
        }
        calendar.timeZone = zone

        let f = DateFormatter()
        f.dateFormat = isUTC ? "yyyyMMdd'T'HHmmss'Z'" : "yyyyMMdd'T'HHmmss"
        f.timeZone = zone
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: trimmed)
    }

    /// Undo RFC 5545 text escaping.
    private static func unescape(_ value: String) -> String {
        var out = ""
        var escaped = false
        for ch in value {
            if escaped {
                switch ch {
                case "n", "N": out.append("\n")
                case "\\": out.append("\\")
                case ",": out.append(",")
                case ";": out.append(";")
                default: out.append(ch)
                }
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else {
                out.append(ch)
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
