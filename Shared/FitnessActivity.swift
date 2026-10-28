import Foundation
import ActivityKit

/// Live Activity payload: today's remaining budget at a glance on the
/// Lock Screen / Dynamic Island. Updated whenever the app saves a change
/// or backgrounds (no server, so it refreshes when the app runs).
struct FitnessActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var caloriesLeft: Int
        var proteinGrams: Int
        var proteinTarget: Int
        var waterOz: Int
        var waterGoal: Int
        var streak: Int

        // Mealtime check-in — the buddy, and the meal it's waiting on.
        // Optional so an activity started by an older build still decodes.
        var buddyAsset: String?
        var buddyName: String?
        /// The meal whose window is open right now and isn't logged.
        var dueMeal: String?
        var dueEnd: Date?
        /// Otherwise the next one. When `nextAt` passes, the activity goes
        /// stale on its own (that's its `staleDate`) and the view flips to
        /// "it's time" — no server, no push.
        var nextMeal: String?
        var nextAt: Date?
        var mealsLogged: Int?
        var mealsPlanned: Int?
    }
}
