import Foundation
import ActivityKit
import UIKit

/// Starts/updates the Lock Screen + Dynamic Island Live Activity: today's
/// remaining budget, plus the studio buddy waiting on the next meal.
///
/// No server, so it refreshes whenever the app runs (foreground work,
/// backgrounding, Siri intents). The one thing that has to happen *without*
/// the app — flipping to "it's lunchtime" — rides on the content's
/// `staleDate`: it's set to the next meal's time, and the view renders the
/// stale state as the prompt.
enum LiveActivityManager {
    static let enabledKey = "liveactivity.enabled"
    private static let startedKey = "liveactivity.startedAt"

    /// On unless switched off — the meal check-in is the point of it.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    @MainActor
    static func sync(plan: Plan, profile: UserProfile) {
        guard isEnabled else {
            endAll()
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let now = Date()
        let cal = Calendar.current
        let targets = CalorieEngine.targets(profile: profile, plan: plan)
        let day = ensureDay(plan: plan, date: now)
        let snapshot = WidgetSnapshot.build(plan: plan, profile: profile, today: day)
        let midnight = cal.startOfDay(for: now.addingTimeInterval(86_400))

        var state = FitnessActivityAttributes.ContentState(
            caloriesLeft: targets.calories - day.totalCalories,
            proteinGrams: day.totalProtein,
            proteinTarget: targets.proteinGrams,
            waterOz: day.waterOunces,
            waterGoal: targets.waterOunces,
            streak: CalorieEngine.streakStats(plan: plan, targets: targets).current)
        state.buddyAsset = WidgetSnapshot.buddyAsset
        state.buddyName = WidgetSnapshot.buddyName
        let progress = snapshot.mealProgress(at: now)
        state.mealsLogged = progress.logged
        state.mealsPlanned = progress.planned

        // Goes stale at the next moment the meal picture changes on its own.
        var stale = midnight
        switch snapshot.mealState(at: now) {
        case let .due(meal, _, end):
            state.dueMeal = meal.label
            state.dueEnd = end
            stale = end
        case let .logged(_, next):
            if let next {
                state.nextMeal = next.0.label
                state.nextAt = next.1
                stale = next.1
            }
        case let .upcoming(meal, at):
            state.nextMeal = meal.label
            state.nextAt = at
            stale = at
        case .wrapped:
            break
        }
        let content = ActivityContent(state: state, staleDate: stale)

        // The system ends a Live Activity after 8 hours. Restart it while the
        // app is open, before that happens, so it lasts the whole day.
        let started = UserDefaults.standard.object(forKey: startedKey) as? Date ?? .distantPast
        // Starting one is only allowed in the foreground, so an aging activity
        // is only swapped out while the app's open; otherwise it's updated.
        let canStart = UIApplication.shared.applicationState == .active
        let aging = canStart && now.timeIntervalSince(started) > 6 * 3600

        if let activity = Activity<FitnessActivityAttributes>.activities.first, !aging {
            Task { await activity.update(content) }
        } else {
            endAll()
            if (try? Activity.request(attributes: FitnessActivityAttributes(), content: content)) != nil {
                UserDefaults.standard.set(now, forKey: startedKey)
            }
        }
    }

    static func endAll() {
        for activity in Activity<FitnessActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
