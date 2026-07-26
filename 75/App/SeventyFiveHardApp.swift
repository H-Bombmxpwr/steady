
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
        #if DEBUG
        // Simulator/UI-test hook: `-seedDemo` fills an empty store with a
        // month of plausible data so screens render without onboarding.
        if CommandLine.arguments.contains("-seedDemo") {
            Self.seedDemoData()
        }
        #endif
    }

    #if DEBUG
    private static func seedDemoData() {
        let context = ModelContext(PersistenceController.shared.container)
        guard ((try? context.fetch(FetchDescriptor<Plan>())) ?? []).isEmpty else { return }
        let cal = Calendar.current
        let profile = UserProfile(birthDate: cal.date(byAdding: .year, value: -30, to: Date())!,
                                  heightInches: 70, sex: .male, activityLevel: .moderate)
        let plan = Plan(startDate: cal.date(byAdding: .day, value: -29, to: Date())!,
                        startingWeight: 230, goalWeight: 200, paceLbsPerWeek: 1.5,
                        proteinTargetGrams: 160)
        context.insert(profile)
        context.insert(plan)
        for i in 0..<30 {
            let date = cal.date(byAdding: .day, value: i, to: plan.startDate)!
            let day = DayLog(date: date)
            // Downhill with believable wobble; every 4th day unlogged.
            if i % 4 != 3 {
                day.weight = ((230 - Double(i) * 0.28 + sin(Double(i)) * 0.8) * 10).rounded() / 10
                day.waterOunces = 64 + (i % 3) * 16
                day.foods.append(FoodLog(name: "Chicken bowl", calories: 650,
                                         proteinGrams: 45, grams: 420, source: "custom",
                                         meal: .lunch))
                day.foods.append(FoodLog(name: "Yogurt + berries", calories: 220,
                                         proteinGrams: 18, grams: 250, source: "custom",
                                         meal: .breakfast))
                if i % 3 == 0 {
                    day.workouts.append(WorkoutLog(name: "Strength", minutes: 45,
                                                   category: .strength))
                }
            }
            plan.days.append(day)
        }
        try? context.save()
    }
    #endif

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
                        refreshStreakGuard()   // also caches the widget snapshot…
                        WidgetCenter.shared.reloadAllTimelines()   // …which this reload reads
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
        LiveActivityManager.sync(plan: plan, profile: profile)
        let targets = CalorieEngine.targets(profile: profile, plan: plan)
        let today = Calendar.current.startOfDay(for: Date())
        let day = plan.days.first { Calendar.current.isDate($0.date, inSameDayAs: today) }
        let met = day.map {
            CalorieEngine.dayCounts(day: $0, plan: plan, targets: targets)
        } ?? false
        let streak = CalorieEngine.streakStats(plan: plan, targets: targets).current
        NotificationManager.updateStreakGuard(todayMet: met, streak: streak)

        // Precompute the widget's numbers here, in the app process — the
        // widget's memory cap can't afford opening the store, let alone
        // walking the full plan graph. Includes today's live totals so the
        // widget renders entirely from this cache.
        WidgetSnapshot.build(plan: plan, profile: profile, today: day).save()
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
                    // Seed the widget cache on launch too, so widgets have
                    // numbers before the app ever hits the background.
                    let today = Calendar.current.startOfDay(for: Date())
                    let day = plan.days.first { Calendar.current.isDate($0.date, inSameDayAs: today) }
                    WidgetSnapshot.build(plan: plan, profile: profile, today: day).save()
                }
        } else {
            OnboardingView()
        }
    }
}
