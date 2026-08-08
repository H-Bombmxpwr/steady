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
    }
}
