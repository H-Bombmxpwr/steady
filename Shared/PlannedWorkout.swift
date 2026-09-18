import Foundation
import SwiftData

/// A session planned for one specific date — imported from TrainingPeaks or
/// entered by hand. This is the athlete dashboard's unit of work.
///
/// It deliberately sits alongside `WorkoutScheduleEntry` rather than replacing
/// it: the weekly schedule ("I lift Mon/Wed/Fri") is the right model for
/// habit-building in weight-loss mode, while a training plan is a sequence of
/// distinct dated sessions that changes week to week. `TrainingSession`
/// flattens both into one shape so nothing downstream has to care which it is.
@Model
final class PlannedWorkout {
    /// Start of the day this session belongs to.
    var date: Date
    var name: String
    var minutes: Int
    var hour: Int
    var minute: Int
    var categoryRaw: String = WorkoutCategory.cardio.rawValue
    var intensityRaw: String = WorkoutIntensity.moderate.rawValue
    /// The coach's notes / workout description, kept verbatim.
    var details: String?
    /// "trainingpeaks" | "manual"
    var source: String = "manual"
    /// The iCalendar UID for imported sessions — the dedupe key, so re-syncing
    /// updates a session in place instead of stacking duplicates.
    var externalID: String?
    /// Planned Training Stress Score, when the source published one. Drives
    /// the intensity inference and the day's carb target.
    var tss: Double?
    var distanceMiles: Double?
    var completedAt: Date?
    var createdAt: Date = Date()

    init(date: Date,
         name: String,
         minutes: Int = 60,
         hour: Int = 7,
         minute: Int = 0,
         category: WorkoutCategory = .cardio,
         intensity: WorkoutIntensity = .moderate,
         details: String? = nil,
         source: String = "manual",
         externalID: String? = nil,
         tss: Double? = nil,
         distanceMiles: Double? = nil) {
        self.date = Calendar.current.startOfDay(for: date)
        self.name = name
        self.minutes = minutes
        self.hour = hour
        self.minute = minute
        self.categoryRaw = category.rawValue
        self.intensityRaw = intensity.rawValue
        self.details = details
        self.source = source
        self.externalID = externalID
        self.tss = tss
        self.distanceMiles = distanceMiles
        self.createdAt = Date()
    }

    var category: WorkoutCategory {
        get { WorkoutCategory(rawValue: categoryRaw) ?? .cardio }
        set { categoryRaw = newValue.rawValue }
    }

    var intensity: WorkoutIntensity {
        get { WorkoutIntensity(rawValue: intensityRaw) ?? .moderate }
        set { intensityRaw = newValue.rawValue }
    }

    var isImported: Bool { source == "trainingpeaks" }

    var timeString: String {
        let comps = DateComponents(hour: hour, minute: minute)
        let date = Calendar.current.date(from: comps) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Unified session

/// One planned session, whatever it came from. Views and the fueling engine
/// take this so they never branch on "weekly schedule vs imported plan".
struct TrainingSession: Identifiable, Hashable {
    enum Origin: Hashable {
        case schedule          // recurring weekday slot
        case planned           // dated, hand-entered
        case trainingPeaks     // dated, imported
        case logged            // already done, reconstructed from the day's log
    }

    let id: String
    let name: String
    let minutes: Int
    let hour: Int
    let minute: Int
    let category: WorkoutCategory
    let intensity: WorkoutIntensity
    let details: String?
    let tss: Double?
    let distanceMiles: Double?
    let origin: Origin
    let completed: Bool
    /// A stable handle for "I'm not doing this one today."
    ///
    /// Derived from content rather than from a SwiftData object id on
    /// purpose: a recurring Monday slot has no per-day object to hang a flag
    /// on, and an object id wouldn't survive being read back on another
    /// launch anyway. Name plus time plus length is specific enough that two
    /// sessions on one day don't collide in practice.
    let skipKey: String

    var timeString: String {
        let comps = DateComponents(hour: hour, minute: minute)
        let date = Calendar.current.date(from: comps) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// "90 min · Hard · 7:00 AM"
    var subtitle: String {
        var parts = ["\(minutes) min", intensity.label]
        if let tss, tss > 0 { parts.append("\(Int(tss.rounded())) TSS") }
        parts.append(timeString)
        return parts.joined(separator: " · ")
    }

    init(_ entry: WorkoutScheduleEntry) {
        self.id = "sched-\(entry.persistentModelID.hashValue)"
        self.name = entry.name
        self.minutes = entry.minutes
        self.hour = entry.hour
        self.minute = entry.minute
        self.category = entry.category
        self.intensity = entry.intensity
        self.details = nil
        self.tss = nil
        self.distanceMiles = nil
        self.origin = .schedule
        self.completed = false
        self.skipKey = TrainingSession.skipKey(name: entry.name, hour: entry.hour,
                                               minute: entry.minute, minutes: entry.minutes)
    }

    /// Build one directly. Everything else about a session is derived, so
    /// this is the seam that lets the fueling and meal-plan math be tested
    /// without a store behind it.
    init(id: String,
         name: String,
         minutes: Int,
         hour: Int,
         minute: Int,
         category: WorkoutCategory,
         intensity: WorkoutIntensity,
         details: String? = nil,
         tss: Double? = nil,
         distanceMiles: Double? = nil,
         origin: Origin = .planned,
         completed: Bool = false,
         skipKey: String? = nil) {
        self.id = id
        self.skipKey = skipKey ?? TrainingSession.skipKey(name: name, hour: hour,
                                                          minute: minute, minutes: minutes)
        self.name = name
        self.minutes = minutes
        self.hour = hour
        self.minute = minute
        self.category = category
        self.intensity = intensity
        self.details = details
        self.tss = tss
        self.distanceMiles = distanceMiles
        self.origin = origin
        self.completed = completed
    }

    /// A workout that already happened, read back off the day's log.
    ///
    /// Someone who never opens a training plan still trains, and the day's
    /// fuel should bend around the session they actually did. This is what
    /// lets the meal plan work in weight-loss and general-health mode, where
    /// nothing is scheduled and the workout only exists after the fact.
    init(_ log: WorkoutLog) {
        self.id = "logged-\(log.persistentModelID.hashValue)"
        self.name = log.name
        self.minutes = log.minutes
        self.hour = log.minutesOfDay / 60
        self.minute = log.minutesOfDay % 60
        self.category = log.category
        self.intensity = log.intensity
        self.details = nil
        self.tss = nil
        self.distanceMiles = nil
        self.origin = .logged
        self.completed = true
        self.skipKey = TrainingSession.skipKey(name: log.name,
                                               hour: log.minutesOfDay / 60,
                                               minute: log.minutesOfDay % 60,
                                               minutes: log.minutes)
    }

    init(_ planned: PlannedWorkout) {
        self.id = "planned-\(planned.persistentModelID.hashValue)"
        self.name = planned.name
        self.minutes = planned.minutes
        self.hour = planned.hour
        self.minute = planned.minute
        self.category = planned.category
        self.intensity = planned.intensity
        self.details = planned.details
        self.tss = planned.tss
        self.distanceMiles = planned.distanceMiles
        self.origin = planned.isImported ? .trainingPeaks : .planned
        self.completed = planned.completedAt != nil
        // An imported session already has a stable identifier of its own.
        self.skipKey = planned.externalID
            ?? TrainingSession.skipKey(name: planned.name, hour: planned.hour,
                                       minute: planned.minute, minutes: planned.minutes)
    }

    static func skipKey(name: String, hour: Int, minute: Int, minutes: Int) -> String {
        "\(name.lowercased())|\(hour):\(minute)|\(minutes)"
    }

    /// Already-finished work can't be un-done by skipping it — the calories
    /// were spent. Only what's still ahead can be called off.
    var canBeSkipped: Bool { origin != .logged }
}
