import Foundation

/// The precomputed numbers the widget needs but must not compute itself.
/// Widget extensions live under a ~30 MB memory cap; walking `plan.days`
/// (which faults every logged day plus its foods/workouts/photos) grows
/// with history and eventually gets the process killed. So the APP writes
/// this tiny snapshot whenever it runs, and the widget reads it back plus
/// one fetch for today's row — O(1) regardless of history size.
struct WidgetSnapshot: Codable {
    var hasPlan = false
    var calorieBudget = 2000
    var proteinTarget = 120
    var waterGoal = 96
    var waterStep = 8
    var streak = 0
    var goalDate: Date?

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
