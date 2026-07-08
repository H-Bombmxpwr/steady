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
        self.days = []
        self.presets = []
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
