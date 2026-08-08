import Foundation
import CoreLocation
#if canImport(WeatherKit)
import WeatherKit
#endif

/// Local conditions for the fueling math, from Apple's WeatherKit.
///
/// WeatherKit was chosen over a third-party API for one reason: no key ships
/// in the binary and no request identifies the user to anyone but Apple. The
/// only thing that leaves the device is a coarse coordinate, and only while
/// athlete mode is actually asking.
///
/// Everything degrades gracefully. If the WeatherKit capability isn't
/// provisioned yet, location is denied, or the network is down, `current`
/// returns nil and the athlete can enter conditions by hand — the sweat and
/// hydration math is identical either way.
@MainActor
final class WeatherService: NSObject, ObservableObject {
    static let shared = WeatherService()

    /// Manual override, used when automatic weather is off or unavailable.
    static let manualTempKey = "weather.manualTempF"
    static let manualHumidityKey = "weather.manualHumidity"
    static let useAutomaticKey = "weather.automatic"

    @Published private(set) var current: WeatherContext?
    @Published private(set) var lastError: String?
    @Published private(set) var isLoading = false

    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    /// Conditions don't move fast enough to justify refetching on every view
    /// appearance, and WeatherKit calls are metered.
    private var fetchedAt: Date?
    private static let cacheLifetime: TimeInterval = 30 * 60

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isAutomaticEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.useAutomaticKey) as? Bool ?? true
    }

    var authorizationDenied: Bool {
        let status = locationManager.authorizationStatus
        return status == .denied || status == .restricted
    }

    /// The conditions to fuel against: live weather when it's available and
    /// switched on, the manual entry otherwise, and nil when there's nothing.
    var effective: WeatherContext? {
        if isAutomaticEnabled, let current { return current }
        return Self.manual
    }

    static var manual: WeatherContext? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: manualTempKey) != nil else { return nil }
        let temp = defaults.double(forKey: manualTempKey)
        let humidity = defaults.object(forKey: manualHumidityKey) as? Double ?? 50
        return WeatherContext(tempF: temp, humidityPercent: humidity,
                              conditionDescription: "Entered by hand")
    }

    static func setManual(tempF: Double, humidityPercent: Double) {
        UserDefaults.standard.set(tempF, forKey: manualTempKey)
        UserDefaults.standard.set(humidityPercent, forKey: manualHumidityKey)
    }

    static func clearManual() {
        UserDefaults.standard.removeObject(forKey: manualTempKey)
        UserDefaults.standard.removeObject(forKey: manualHumidityKey)
    }

    /// Refresh if the cache is stale. Safe to call from `.task` on any view —
    /// it will never raise the location prompt, so a dashboard appearing
    /// doesn't ambush someone with a permission sheet before they've seen it.
    func refreshIfNeeded() async {
        guard isAutomaticEnabled else { return }
        if let fetchedAt, Date().timeIntervalSince(fetchedAt) < Self.cacheLifetime,
           current != nil { return }
        await refresh(promptForPermission: false)
    }

    /// - Parameter promptForPermission: only true when the user just asked for
    ///   this — flipping the weather switch in Settings or onboarding. That's
    ///   the moment the system prompt makes sense, because the ask has context.
    func refresh(promptForPermission: Bool = true) async {
        #if canImport(WeatherKit)
        guard isAutomaticEnabled else { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let location = try await requestLocation(promptForPermission: promptForPermission)
            let weather = try await WeatherKit.WeatherService.shared.weather(for: location)
            let temp = weather.currentWeather.temperature.converted(to: .fahrenheit).value
            let humidity = weather.currentWeather.humidity * 100
            current = WeatherContext(tempF: temp,
                                     humidityPercent: humidity,
                                     conditionDescription: weather.currentWeather.condition.description)
            fetchedAt = Date()
            lastError = nil
        } catch {
            current = nil
            lastError = friendlyMessage(for: error)
        }
        #else
        lastError = "Weather isn't available in this build."
        #endif
    }

    private func friendlyMessage(for error: Error) -> String {
        if locationManager.authorizationStatus == .notDetermined {
            return "Turn “Use my location” off and on to allow location access, or enter conditions by hand below."
        }
        if authorizationDenied {
            return "Location is off for Steady, so conditions can't be fetched. Enter them by hand below, or allow location in iOS Settings → Privacy → Location Services."
        }
        if (error as? CLError)?.code == .denied {
            return "Location permission was declined. Enter conditions by hand below."
        }
        return "Couldn't fetch conditions (\(error.localizedDescription)). Enter them by hand below."
    }

    // MARK: - Location

    private func requestLocation(promptForPermission: Bool) async throws -> CLLocation {
        if let cached = locationManager.location,
           Date().timeIntervalSince(cached.timestamp) < 15 * 60 {
            return cached
        }
        if locationManager.authorizationStatus == .notDetermined {
            guard promptForPermission else { throw CLError(.denied) }
            locationManager.requestWhenInUseAuthorization()
        }
        guard !authorizationDenied else { throw CLError(.denied) }

        return try await withCheckedThrowingContinuation { continuation in
            // A second request while one is in flight would strand the first.
            if locationContinuation != nil {
                continuation.resume(throwing: CLError(.locationUnknown))
                return
            }
            locationContinuation = continuation
            locationManager.requestLocation()
        }
    }
}

extension WeatherService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let continuation = self.locationContinuation else { return }
            self.locationContinuation = nil
            if let location = locations.last {
                continuation.resume(returning: location)
            } else {
                continuation.resume(throwing: CLError(.locationUnknown))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in
            guard let continuation = self.locationContinuation else { return }
            self.locationContinuation = nil
            continuation.resume(throwing: error)
        }
    }
}
