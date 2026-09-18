import Foundation
import SwiftData

/// One meal in the shape of a day: when it happens and how much of the day's
/// food it's expected to carry.
///
/// The schedule is a *template*, not a contract. It says "I normally eat
/// breakfast around seven and dinner is my big one" — the day plan then bends
/// it around whatever actually happened: a late wake-up, a session at 6 a.m.,
/// a meal that got skipped. Shares are relative weights rather than
/// percentages so adding or removing a slot never requires re-balancing the
/// others by hand; the engine normalizes whatever is left.
@Model
final class MealSlot {
    var mealRaw: String
    var hour: Int
    var minute: Int
    /// Relative size against the other enabled slots. Normalized at plan time,
    /// so 1.0 / 1.2 / 1.4 and 25 / 30 / 35 describe the same day.
    var share: Double
    var enabled: Bool
    var orderIndex: Int
    /// Overrides the meal's own name when someone eats on a schedule the
    /// stock labels don't describe ("Second breakfast", "Night shift meal").
    var customName: String?

    init(meal: Meal, hour: Int, minute: Int = 0, share: Double = 1.0,
         enabled: Bool = true, orderIndex: Int = 0, customName: String? = nil) {
        self.mealRaw = meal.rawValue
        self.hour = hour
        self.minute = minute
        self.share = share
        self.enabled = enabled
        self.orderIndex = orderIndex
        self.customName = customName
    }

    var meal: Meal {
        get { Meal(rawValue: mealRaw) ?? .lunch }
        set { mealRaw = newValue.rawValue }
    }

    var label: String {
        let custom = (customName ?? "").trimmingCharacters(in: .whitespaces)
        return custom.isEmpty ? meal.label : custom
    }

    /// Minutes past midnight — the sort key for the whole timeline.
    var minutesOfDay: Int { hour * 60 + minute }

    var timeString: String {
        let comps = DateComponents(hour: hour, minute: minute)
        let date = Calendar.current.date(from: comps) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// The starting schedule: three meals with dinner carrying the most, plus
    /// two snacks and a dessert slot switched off. Athletes with big carb
    /// targets turn the snacks on; most people never touch this screen.
    static func defaultSchedule() -> [MealSlot] {
        [
            MealSlot(meal: .breakfast,      hour: 7,  minute: 0,  share: 1.0, enabled: true,  orderIndex: 0),
            MealSlot(meal: .morningSnack,   hour: 10, minute: 0,  share: 0.4, enabled: false, orderIndex: 1),
            MealSlot(meal: .lunch,          hour: 12, minute: 30, share: 1.2, enabled: true,  orderIndex: 2),
            MealSlot(meal: .afternoonSnack, hour: 15, minute: 30, share: 0.4, enabled: false, orderIndex: 3),
            MealSlot(meal: .dinner,         hour: 18, minute: 30, share: 1.4, enabled: true,  orderIndex: 4),
            MealSlot(meal: .dessert,        hour: 20, minute: 30, share: 0.3, enabled: false, orderIndex: 5)
        ]
    }
}
