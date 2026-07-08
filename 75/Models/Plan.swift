import Foundation
import SwiftData

@Model
final class Plan {
    var createdAt: Date
    var startDate: Date
    var startingWeight: Double        // lb
    var goalWeight: Double            // lb
    var paceLbsPerWeek: Double        // target loss rate
    var waterGoalOunces: Int
    var waterStepOunces: Int
    var proteinTargetGrams: Int
    var calorieBudgetOverride: Int?   // nil = use computed budget

    @Relationship(deleteRule: .cascade) var days: [DayLog]
    @Relationship(deleteRule: .cascade) var presets: [WorkoutPreset]
    @Relationship(deleteRule: .cascade) var schedule: [WorkoutScheduleEntry]
    @Relationship(deleteRule: .cascade) var supplements: [Supplement]

    init(startDate: Date,
         startingWeight: Double,
         goalWeight: Double,
         paceLbsPerWeek: Double,
         waterGoalOunces: Int = 96,
         waterStepOunces: Int = 8,
         proteinTargetGrams: Int) {
        self.createdAt = Date()
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.startingWeight = startingWeight
        self.goalWeight = goalWeight
        self.paceLbsPerWeek = paceLbsPerWeek
        self.waterGoalOunces = waterGoalOunces
        self.waterStepOunces = max(1, waterStepOunces)
        self.proteinTargetGrams = proteinTargetGrams
        self.calorieBudgetOverride = nil
        self.days = []
        self.presets = []
        self.schedule = []
        self.supplements = []
    }

    /// Most recent logged weight, falling back to the starting weight.
    var currentWeight: Double {
        let logged = days
            .filter { $0.weight != nil }
            .sorted { $0.date < $1.date }
            .last?.weight
        return logged ?? startingWeight
    }

    var weightChange: Double { currentWeight - startingWeight }

    /// Estimated date the goal weight is reached at the chosen pace.
    var projectedGoalDate: Date? {
        guard paceLbsPerWeek > 0, currentWeight > goalWeight else { return nil }
        let weeks = (currentWeight - goalWeight) / paceLbsPerWeek
        return Calendar.current.date(byAdding: .day, value: Int(weeks * 7), to: Date())
    }

    /// Is a workout planned for this date's weekday?
    func isWorkoutScheduled(on date: Date) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        return schedule.contains { $0.weekday == weekday }
    }

    func scheduledWorkouts(on date: Date) -> [WorkoutScheduleEntry] {
        let weekday = Calendar.current.component(.weekday, from: date)
        return schedule.filter { $0.weekday == weekday }
    }
}

@Model
final class WorkoutPreset {
    var name: String
    var defaultMinutes: Int
    var outdoor: Bool
    var notes: String?

    init(name: String, defaultMinutes: Int = 45, outdoor: Bool = false, notes: String? = nil) {
        self.name = name
        self.defaultMinutes = defaultMinutes
        self.outdoor = outdoor
        self.notes = notes
    }
}

/// One planned workout slot per weekday (weekday: 1 = Sunday … 7 = Saturday).
@Model
final class WorkoutScheduleEntry {
    var weekday: Int
    var name: String
    var minutes: Int
    var hour: Int                     // planned start time (for reminders/calendar)
    var minute: Int
    var calendarEventID: String?      // EventKit identifier once synced

    init(weekday: Int, name: String, minutes: Int = 45, hour: Int = 7, minute: Int = 0) {
        self.weekday = weekday
        self.name = name
        self.minutes = minutes
        self.hour = hour
        self.minute = minute
        self.calendarEventID = nil
    }

    var weekdayName: String {
        Calendar.current.weekdaySymbols[max(0, min(6, weekday - 1))]
    }

    var timeString: String {
        let comps = DateComponents(hour: hour, minute: minute)
        let date = Calendar.current.date(from: comps) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

@Model
final class Supplement {
    var name: String
    var hour: Int                     // daily reminder time
    var minute: Int
    var remind: Bool
    var createdAt: Date

    init(name: String, hour: Int = 8, minute: Int = 0, remind: Bool = true) {
        self.name = name
        self.hour = hour
        self.minute = minute
        self.remind = remind
        self.createdAt = Date()
    }

    var timeString: String {
        let comps = DateComponents(hour: hour, minute: minute)
        let date = Calendar.current.date(from: comps) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
