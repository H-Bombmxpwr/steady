import Foundation

/// Eating-window tracking (16:8-style, opt-in). No new logging: the window
/// is derived from when foods were logged — first food opens it, last food
/// closes it, and the fast is simply the time since the last food.
enum Fasting {
    static let enabledKey = "fasting.enabled"
    static let targetHoursKey = "fasting.targetHours"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Target fast length in hours (16 = the classic 16:8).
    static var targetHours: Int {
        let v = UserDefaults.standard.integer(forKey: targetHoursKey)
        return v == 0 ? 16 : v
    }

    struct Status {
        let lastFood: Date          // when the current fast started
        let firstFoodToday: Date?   // today's window opened (nil = still fasting)

        func fastedHours(at now: Date) -> Double {
            max(0, now.timeIntervalSince(lastFood) / 3600)
        }
    }

    /// Current fast, from the most recent food logged in the last few days.
    /// Nil until there's at least one logged food to anchor the clock.
    static func status(plan: Plan, now: Date = Date()) -> Status? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let cutoff = cal.date(byAdding: .day, value: -3, to: today) else { return nil }
        let recentFoods = plan.days
            .filter { $0.date >= cutoff }
            .flatMap(\.foods)
            .filter { $0.createdAt <= now }
        guard let lastFood = recentFoods.map(\.createdAt).max() else { return nil }
        let firstToday = recentFoods
            .filter { cal.isDate($0.createdAt, inSameDayAs: now) }
            .map(\.createdAt).min()
        return Status(lastFood: lastFood, firstFoodToday: firstToday)
    }

    /// Hours between the first and last food of each day — the chartable
    /// history. Days with one food count as a zero-length window.
    static func eatingWindows(days: [DayLog]) -> [(date: Date, hours: Double)] {
        days.compactMap { day in
            let times = day.foods.map(\.createdAt)
            guard let first = times.min(), let last = times.max() else { return nil }
            return (date: day.date, hours: last.timeIntervalSince(first) / 3600)
        }
    }
}
