
import SwiftUI
import SwiftData
import Combine

@main
struct SeventyFiveHardApp: App {
    var sharedModelContainer: ModelContainer = PersistenceController.shared.container
    @StateObject private var appLock = AppLockManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPrivacyShield = true

    var body: some Scene {
        WindowGroup {
            RootRouterView()
                .modelContainer(sharedModelContainer)
                .environmentObject(appLock)
                // FaceID gate
                .overlay(alignment: .center) {
                    if !appLock.isUnlocked {
                        LockGateView().environmentObject(appLock).ignoresSafeArea()
                    }
                }
                // Privacy blur when backgrounded/app switcher
                .overlay(alignment: .center) {
                    if showPrivacyShield { PrivacyShieldView() }
                }
                .onChange(of: scenePhase) { phase in
                    switch phase {
                    case .active:
                        showPrivacyShield = false
                        appLock.authenticateIfNeeded()
                    case .inactive, .background:
                        showPrivacyShield = true
                        appLock.lock()
                    @unknown default:
                        showPrivacyShield = true
                        appLock.lock()
                    }
                }
                .task {
                    // First launch: start shield, then immediately auth
                    showPrivacyShield = true
                    appLock.authenticateIfNeeded()
                }
        }
    }
}

struct RootRouterView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Plan.createdAt, order: .forward) private var plans: [Plan]
    @Query(sort: \UserProfile.createdAt, order: .forward) private var profiles: [UserProfile]

    var body: some View {
        if let plan = plans.first, let profile = profiles.first {
            MainTabView(plan: plan, profile: profile)
        } else {
            OnboardingView()
        }
    }
}
