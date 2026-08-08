
import SwiftUI
import LocalAuthentication
import CryptoKit
import Security

/// Backup PIN for the private areas of the app, for when Face ID fails or the
/// user would rather not use it. Only a salted SHA-256 digest is kept, in the
/// Keychain (this-device-only, never in backups).
///
/// The keychain account and salt still say "photos" because that's what this
/// PIN originally guarded — renaming them would silently invalidate every
/// PIN already set on a device.
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

/// The parts of the app that stay locked until Face ID (or the backup PIN)
/// says otherwise. Not app entry — just the things you'd rather a person
/// holding your unlocked phone couldn't scroll past.
enum ProtectedArea: String, CaseIterable, Identifiable {
    case photos
    case cycle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photos: return "Photos Locked"
        case .cycle: return "Cycle Log Locked"
        }
    }

    /// Shown by the system in the Face ID prompt.
    var reason: String {
        switch self {
        case .photos: return "Unlock to view your progress photos"
        case .cycle: return "Unlock to view your cycle log"
        }
    }
}

/// Face ID (with the PIN as backup) guards the private areas listed in
/// `ProtectedArea` — not app entry. Everything re-locks whenever the app
/// leaves the foreground, so handing someone your phone doesn't hand them
/// your photos or your cycle history.
final class AppLockManager: ObservableObject {
    @Published private(set) var unlockedAreas: Set<ProtectedArea> = []

    var biometricsAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func isUnlocked(_ area: ProtectedArea) -> Bool { unlockedAreas.contains(area) }

    func lock(_ area: ProtectedArea) { unlockedAreas.remove(area) }

    func lockAll() { unlockedAreas.removeAll() }

    func unlock(_ area: ProtectedArea) {
        guard !isUnlocked(area) else { return }
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication,
                                   localizedReason: area.reason) { success, _ in
                DispatchQueue.main.async {
                    if success { self.unlockedAreas.insert(area) }
                }
            }
        }
    }

    @discardableResult
    func unlockWithPIN(_ pin: String, for area: ProtectedArea) -> Bool {
        guard PinStore.verify(pin) else { return false }
        unlockedAreas.insert(area)
        return true
    }

    // MARK: Photo-flavored shorthands, kept so the photo screens read the
    // way they always did.

    var photosUnlocked: Bool { isUnlocked(.photos) }
    func lockPhotos() { lock(.photos) }
    func unlockPhotos() { unlock(.photos) }

    @discardableResult
    func unlockWithPIN(_ pin: String) -> Bool { unlockWithPIN(pin, for: .photos) }
}

/// Placeholder shown wherever a protected area lives until Face ID or the PIN
/// unlocks it.
struct LockGate: View {
    @EnvironmentObject private var appLock: AppLockManager
    var area: ProtectedArea = .photos
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
                Text(area.title).font(.title3.bold())
            }
            if appLock.biometricsAvailable {
                Button(action: { appLock.unlock(area) }) {
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
                        if appLock.unlockWithPIN(pin, for: area) {
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

/// The photo-specific gate, unchanged at every call site.
struct PhotoLockGate: View {
    var compact = false
    var body: some View { LockGate(area: .photos, compact: compact) }
}
