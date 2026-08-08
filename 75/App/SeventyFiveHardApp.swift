
import SwiftUI
import SwiftData
import UserNotifications
import WidgetKit

@main
struct SeventyFiveHardApp: App {
    var sharedModelContainer: ModelContainer = PersistenceController.shared.container
    @StateObject private var appLock = AppLockManager()
    @Environment(\.scenePhase) private var scenePhase
    /// App-switcher privacy cover (branded, not a lock). Off until the app
    /// has been active once, so it never flashes over the launch screen.
    @State private var showPrivacyShield = false
    @State private var hasBecomeActive = false
    /// Cold-launch loading screen, dismissed once its progress bar fills.
    @State private var launching = true

    private static let notificationDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = Self.notificationDelegate
        NotificationManager.registerCategories()
        #if DEBUG
        // Simulator/UI-test hooks: `-seedDemo` fills an empty store with a
        // month of plausible weight-loss data, `-seedAthlete` does the same
        // for athlete mode, so screens render without walking onboarding.
        // Both no-op on a non-empty store, so `-resetStore` clears it first —
        // UI tests share one container and would otherwise inherit whichever
        // mode the previous test seeded.
        if CommandLine.arguments.contains("-resetStore") {
            Self.resetStore()
        }
        if CommandLine.arguments.contains("-seedDemo") {
            Self.seedDemoData()
        }
        if CommandLine.arguments.contains("-seedAthlete") {
            Self.seedAthleteData()
        }
        #endif
    }

    #if DEBUG
    /// Wipe every plan and profile. The cascade rules take the days, foods,
    /// workouts, sweat tests, and cycles with them.
    private static func resetStore() {
        let context = ModelContext(PersistenceController.shared.container)
        for plan in (try? context.fetch(FetchDescriptor<Plan>())) ?? [] {
            context.delete(plan)
        }
        for profile in (try? context.fetch(FetchDescriptor<UserProfile>())) ?? [] {
            context.delete(profile)
        }
        try? context.save()
    }

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

    /// An athlete mid-training-block: a dated plan for the week, a couple of
    /// sweat tests, and cycle history — enough for every athlete-mode card to
    /// render with real numbers.
    private static func seedAthleteData() {
        let context = ModelContext(PersistenceController.shared.container)
        guard ((try? context.fetch(FetchDescriptor<Plan>())) ?? []).isEmpty else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        let profile = UserProfile(birthDate: cal.date(byAdding: .year, value: -34, to: Date())!,
                                  heightInches: 68, sex: .female, activityLevel: .moderate,
                                  mode: .athlete, generalHealth: true)
        profile.cycleTracking = true
        profile.cycleTrackingOffered = true

        let plan = Plan(startDate: cal.date(byAdding: .day, value: -29, to: today)!,
                        startingWeight: 142, goalWeight: 142, paceLbsPerWeek: 0,
                        proteinTargetGrams: 115)
        plan.eatAtMaintenance = true
        context.insert(profile)
        context.insert(plan)

        // A month of logging, with weight holding steady the way it should
        // during a block that's fuelled properly.
        for i in 0..<30 {
            let date = cal.date(byAdding: .day, value: i - 29, to: today)!
            let day = DayLog(date: date)
            day.weight = ((142 + sin(Double(i) / 3) * 0.7) * 10).rounded() / 10
            day.waterOunces = 80 + (i % 3) * 16
            day.foods.append(FoodLog(name: "Oats, banana, peanut butter", calories: 620,
                                     proteinGrams: 20, grams: 380, source: "custom",
                                     meal: .breakfast,
                                     facts: NutritionFacts(carbsGrams: 92, fatGrams: 18,
                                                           fiberGrams: 11, sugarGrams: 22)))
            day.foods.append(FoodLog(name: "Chicken, rice, greens", calories: 780,
                                     proteinGrams: 52, grams: 520, source: "custom",
                                     meal: .dinner,
                                     facts: NutritionFacts(carbsGrams: 96, fatGrams: 18,
                                                           sodiumMg: 780, fiberGrams: 8)))
            if i % 7 != 0 {
                day.workouts.append(WorkoutLog(name: "Endurance ride", minutes: 75,
                                               category: .cardio))
            }
            plan.days.append(day)
        }

        // This week's plan — the shape of a real block: a big weekend ride,
        // intervals midweek, a lifting day, and a genuine rest day.
        let week: [(offset: Int, name: String, minutes: Int, category: WorkoutCategory,
                    intensity: WorkoutIntensity, tss: Double?, hour: Int)] = [
            (0, "Threshold 3x12", 90, .cardio, .hard, 95, 6),
            (0, "Core & Mobility", 25, .mobility, .easy, nil, 19),
            (1, "Recovery Spin", 45, .cardio, .easy, 28, 7),
            (2, "Strength — Lower", 60, .strength, .moderate, nil, 17),
            (3, "Endurance Ride", 150, .cardio, .moderate, 130, 6),
            (5, "Long Ride", 240, .cardio, .moderate, 210, 7),
            (6, "Brick — Ride + Run", 120, .cardio, .hard, 140, 8)
        ]
        for entry in week {
            plan.plannedWorkouts.append(
                PlannedWorkout(date: cal.date(byAdding: .day, value: entry.offset, to: today)!,
                               name: entry.name,
                               minutes: entry.minutes,
                               hour: entry.hour,
                               category: entry.category,
                               intensity: entry.intensity,
                               details: "Seeded demo session.",
                               source: "trainingpeaks",
                               externalID: "demo-\(entry.offset)-\(entry.name)",
                               tss: entry.tss))
        }
        plan.trainingPeaksFeedURL = "https://www.trainingpeaks.com/ical/DEMO.ics"
        plan.trainingPeaksLastSync = Date()

        // Two sweat tests in different conditions.
        plan.sweatTests.append(SweatTest(date: cal.date(byAdding: .day, value: -21, to: today)!,
                                         preWeightLbs: 142.4, postWeightLbs: 140.9,
                                         fluidOunces: 20, minutes: 75,
                                         category: .cardio, intensity: .moderate,
                                         tempF: 58, humidityPercent: 60))
        plan.sweatTests.append(SweatTest(date: cal.date(byAdding: .day, value: -6, to: today)!,
                                         preWeightLbs: 142.1, postWeightLbs: 140.0,
                                         fluidOunces: 26, minutes: 80,
                                         category: .cardio, intensity: .hard,
                                         tempF: 81, humidityPercent: 55))

        // Three cycles of history, currently mid-luteal.
        for offset in [58, 30, 2] {
            let start = cal.date(byAdding: .day, value: -offset - 18, to: today)!
            let entry = CycleEntry(startDate: start,
                                   endDate: cal.date(byAdding: .day, value: 4, to: start)!)
            entry.symptoms = ["Cramps", "Fatigue"]
            plan.cycles.append(entry)
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
                // Branded privacy cover in the app switcher / when backgrounded.
                .overlay { if showPrivacyShield { PrivacyShieldView() } }
                // Themed launch screen on top, until its progress bar fills.
                .overlay {
                    if launching {
                        LaunchLoadingView {
                            withAnimation(.easeOut(duration: 0.35)) { launching = false }
                        }
                        .transition(.opacity)
                    }
                }
                .onChange(of: scenePhase) { phase in
                    switch phase {
                    case .active:
                        hasBecomeActive = true
                        showPrivacyShield = false
                    case .inactive, .background:
                        // Don't cover the launch screen before the first activation.
                        if hasBecomeActive { showPrivacyShield = true }
                        appLock.lockAll()      // photos and cycle log re-lock on return
                        refreshStreakGuard()   // also caches the widget snapshot…
                        WidgetCenter.shared.reloadAllTimelines()   // …which this reload reads
                    @unknown default:
                        if hasBecomeActive { showPrivacyShield = true }
                        appLock.lockAll()
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
