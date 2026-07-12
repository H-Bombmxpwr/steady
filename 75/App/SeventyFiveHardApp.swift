
import SwiftUI
import SwiftData
import UserNotifications
import WidgetKit

@main
struct SeventyFiveHardApp: App {
    var sharedModelContainer: ModelContainer = PersistenceController.shared.container
    @StateObject private var appLock = AppLockManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPrivacyShield = true

    private static let notificationDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = Self.notificationDelegate
        NotificationManager.registerCategories()
    }

    var body: some Scene {
        WindowGroup {
            RootRouterView()
                .modelContainer(sharedModelContainer)
                .environmentObject(appLock)
                .themedRoot()
                // Privacy blur when backgrounded/app switcher
                .overlay(alignment: .center) {
                    if showPrivacyShield { PrivacyShieldView() }
                }
                .onChange(of: scenePhase) { phase in
                    switch phase {
                    case .active:
                        showPrivacyShield = false
                    case .inactive, .background:
                        showPrivacyShield = true
                        appLock.lockPhotos()   // photos require Face ID again on return
                        WidgetCenter.shared.reloadAllTimelines()
                        refreshStreakGuard()
                    @unknown default:
                        showPrivacyShield = true
                        appLock.lockPhotos()
                    }
                }
        }
    }

    /// Re-evaluates the streak-at-risk notification whenever the app backgrounds.
    private func refreshStreakGuard() {
        let context = ModelContext(PersistenceController.shared.container)
        guard let plan = try? context.fetch(FetchDescriptor<Plan>()).first,
              let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first else { return }
        let targets = CalorieEngine.targets(profile: profile, plan: plan)
        let today = Calendar.current.startOfDay(for: Date())
        let day = plan.days.first { Calendar.current.isDate($0.date, inSameDayAs: today) }
        let met = day.map {
            CalorieEngine.dayCounts(day: $0, plan: plan, targets: targets)
        } ?? false
        let streak = CalorieEngine.streakStats(plan: plan, targets: targets).current
        NotificationManager.updateStreakGuard(todayMet: met, streak: streak)
    }
}

/// Handles notification actions (e.g. "Log a bottle" on hydration nudges)
/// and keeps banners visible while the app is foregrounded.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == NotificationManager.logWaterAction else { return }
        let context = ModelContext(PersistenceController.shared.container)
        if let plan = try? context.fetch(FetchDescriptor<Plan>()).first {
            let day = ensureDay(plan: plan, date: Date())
            day.waterOunces += max(1, plan.waterStepOunces)
            try? context.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

struct RootRouterView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Plan.createdAt, order: .forward) private var plans: [Plan]
    @Query(sort: \UserProfile.createdAt, order: .forward) private var profiles: [UserProfile]

    var body: some View {
        if let plan = plans.first, let profile = profiles.first {
            MainTabView(plan: plan, profile: profile)
                .task {
                    _ = await NotificationManager.requestAuthorization()
                    NotificationManager.rescheduleAll(plan: plan)
                }
        } else {
            OnboardingView()
        }
    }
}
