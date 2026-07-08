
import SwiftUI
import LocalAuthentication

/// Face ID now guards only the progress photos, not app entry.
/// Photos re-lock whenever the app leaves the foreground.
final class AppLockManager: ObservableObject {
    @Published var photosUnlocked: Bool = false

    func lockPhotos() { photosUnlocked = false }

    func unlockPhotos() {
        guard !photosUnlocked else { return }
        let context = LAContext()
        var error: NSError?
        let reason = "Unlock to view your progress photos"

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                DispatchQueue.main.async { self.photosUnlocked = success }
            }
        } else {
            DispatchQueue.main.async { self.photosUnlocked = false }
        }
    }
}

/// Placeholder shown wherever photos live until Face ID unlocks them.
struct PhotoLockGate: View {
    @EnvironmentObject private var appLock: AppLockManager
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 8 : 20) {
            Image(systemName: "lock.circle.fill")
                .font(.system(size: compact ? 32 : 64))
                .foregroundStyle(Theme.gradient)
            if !compact {
                Text("Photos Locked").font(.title3.bold())
            }
            Button(action: { appLock.unlockPhotos() }) {
                Label("Unlock with Face ID", systemImage: "faceid")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(compact ? 12 : 40)
    }
}
