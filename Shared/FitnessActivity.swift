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
    }
}
