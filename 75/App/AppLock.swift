
import SwiftUI
import LocalAuthentication
import CryptoKit
import Security

/// Backup PIN for the photo lock, for when Face ID fails or the user would
/// rather not use it. Only a salted SHA-256 digest is kept, in the Keychain
/// (this-device-only, never in backups).
enum PinStore {
    private static let service = "com.hunter.seventyfivehard"
    private static let account = "photos.pin"

    static var isSet: Bool { readDigest() != nil }

    static func set(_ pin: String) {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = digest(pin)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    static func clear() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }

    static func verify(_ pin: String) -> Bool {
        guard let stored = readDigest() else { return false }
        return stored == digest(pin)
    }

    private static func digest(_ pin: String) -> Data {
        Data(SHA256.hash(data: Data(("75-photos-pin:" + pin).utf8)))
    }

    private static func readDigest() -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }
}

/// Face ID (with the PIN as backup) guards only the progress photos, not app
/// entry. Photos re-lock whenever the app leaves the foreground.
final class AppLockManager: ObservableObject {
    @Published var photosUnlocked: Bool = false

    var biometricsAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

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

    @discardableResult
    func unlockWithPIN(_ pin: String) -> Bool {
        guard PinStore.verify(pin) else { return false }
        photosUnlocked = true
        return true
    }
}

/// Placeholder shown wherever photos live until Face ID or the PIN unlocks them.
struct PhotoLockGate: View {
    @EnvironmentObject private var appLock: AppLockManager
    var compact = false

    @State private var pin = ""
    @State private var wrongPin = false
    @FocusState private var pinFocused: Bool

    var body: some View {
        VStack(spacing: compact ? 8 : 20) {
            Image(systemName: "lock.circle.fill")
                .font(.system(size: compact ? 32 : 64))
                .foregroundStyle(Theme.gradient)
            if !compact {
                Text("Photos Locked").font(.title3.bold())
            }
            if appLock.biometricsAvailable {
                Button(action: { appLock.unlockPhotos() }) {
                    Label("Unlock with Face ID", systemImage: "faceid")
                }
                .buttonStyle(.borderedProminent)
            }
            if PinStore.isSet && !compact {
                HStack {
                    SecureField("Backup PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($pinFocused)
                        .frame(maxWidth: 160)
                    Button("Unlock") {
                        if appLock.unlockWithPIN(pin) {
                            pin = ""
                            wrongPin = false
                        } else {
                            wrongPin = true
                            pin = ""
                        }
                        pinFocused = false
                    }
                    .buttonStyle(.bordered)
                    .disabled(pin.count < 4)
                }
                if wrongPin {
                    Text("Wrong PIN — try again.")
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }
            } else if !appLock.biometricsAvailable && !compact {
                Text("Face ID isn't available and no backup PIN is set. Add one in Settings → Security.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(compact ? 12 : 40)
    }
}
