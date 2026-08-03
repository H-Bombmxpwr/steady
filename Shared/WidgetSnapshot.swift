import Foundation

/// The precomputed numbers the widget needs but must not compute itself.
/// Widget extensions live under a ~30 MB memory cap; opening the SwiftData
/// stack (let alone walking `plan.days`, which faults every logged day plus
/// its foods/workouts/photos) can spike past that at render time and get the
/// process killed. So the APP writes this tiny snapshot — targets, streak,
/// AND today's live totals — whenever it runs, and the widget only reads it
/// back. The render path never touches the database.
struct WidgetSnapshot: Codable {
    var hasPlan = false
    var calorieBudget = 2000
    var proteinTarget = 120
    var waterGoal = 96
    var waterStep = 8
    var streak = 0
    var goalDate: Date?

    // Today's live totals + the day they belong to, so the widget can tell a
    // fresh snapshot from a stale one (app hasn't run since midnight) without
    // a fetch.
    var caloriesEaten = 0
    var protein = 0
    var waterOz = 0
    var dayDate: Date?

    // Extra stats the large widget has room for.
    var currentWeight: Double = 0    // latest logged weight (lb)
    var startingWeight: Double = 0   // to show pounds lost
    var carbs = 0                    // today's carbs (g)
    var workoutMinutes = 0           // today's logged workout minutes

    static let key = "widget.snapshot"

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroupID)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults(suiteName: appGroupID)?.set(data, forKey: Self.key)
        }
    }
}

extension WidgetSnapshot {
    /// Build the full cache the widget reads — targets, streak, and today's
    /// live totals. This walks history for the streak, so it must run in the
    /// APP process only; the widget just calls `load()`.
    static func build(plan: Plan, profile: UserProfile, today: DayLog?) -> WidgetSnapshot {
        let targets = CalorieEngine.targets(profile: profile, plan: plan)
        var s = WidgetSnapshot()
        s.hasPlan = true
        s.calorieBudget = targets.calories
        s.proteinTarget = targets.proteinGrams
        s.waterGoal = targets.waterOunces
        s.waterStep = max(1, plan.waterStepOunces)
        s.streak = CalorieEngine.streakStats(plan: plan, targets: targets).current
        s.goalDate = plan.projectedGoalDate
        s.caloriesEaten = today?.totalCalories ?? 0
        s.protein = today?.totalProtein ?? 0
        s.waterOz = today?.waterOunces ?? 0
        s.dayDate = Calendar.current.startOfDay(for: Date())
        s.currentWeight = plan.currentWeight
        s.startingWeight = plan.startingWeight
        s.carbs = Int((today?.totalFacts.carbsGrams ?? 0).rounded())
        s.workoutMinutes = today?.workouts.reduce(0) { $0 + $1.minutes } ?? 0
        return s
    }
}
