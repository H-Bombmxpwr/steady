import Foundation
import ActivityKit

/// Starts/updates the Lock Screen + Dynamic Island Live Activity with
/// today's remaining budget. No server, so it refreshes whenever the app
/// runs (foreground work, backgrounding, Siri intents).
enum LiveActivityManager {
    static let enabledKey = "liveactivity.enabled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func sync(plan: Plan, profile: UserProfile) {
        guard isEnabled else {
            endAll()
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let targets = CalorieEngine.targets(profile: profile, plan: plan)
        let day = ensureDay(plan: plan, date: Date())
        let state = FitnessActivityAttributes.ContentState(
            caloriesLeft: targets.calories - day.totalCalories,
            proteinGrams: day.totalProtein,
            proteinTarget: targets.proteinGrams,
            waterOz: day.waterOunces,
            waterGoal: targets.waterOunces,
            streak: CalorieEngine.streakStats(plan: plan, targets: targets).current)
        // Stale after the day rolls over so yesterday's numbers don't linger.
        let content = ActivityContent(state: state,
                                      staleDate: Calendar.current.startOfDay(
                                        for: Date().addingTimeInterval(86_400)))

        if let activity = Activity<FitnessActivityAttributes>.activities.first {
            Task { await activity.update(content) }
        } else {
            _ = try? Activity.request(attributes: FitnessActivityAttributes(),
                                      content: content)
        }
    }

    static func endAll() {
        for activity in Activity<FitnessActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
