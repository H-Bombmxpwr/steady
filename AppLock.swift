
import SwiftUI
import LocalAuthentication

final class AppLockManager: ObservableObject {
    @Published var isUnlocked: Bool = false

    func lock() { isUnlocked = false }

    func authenticateIfNeeded() {
        guard !isUnlocked else { return }
        let context = LAContext()
        var error: NSError?
        let reason = "Unlock to access your 75 Hard data"

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                DispatchQueue.main.async { self.isUnlocked = success }
            }
        } else {
            DispatchQueue.main.async { self.isUnlocked = false }
        }
    }
}

struct LockGateView: View {
    @EnvironmentObject private var appLock: AppLockManager
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.circle.fill").font(.system(size: 64))
            Text("Face ID Required").font(.title2.bold())
            Text("Unlock to continue").foregroundStyle(.secondary)
            Button(action: { appLock.authenticateIfNeeded() }) {
                Label("Unlock", systemImage: "faceid")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
