import Foundation
import CoreLocation

/// Roughly where you are, once, for the one feature that needs it.
///
/// "Healthy things near me" can't work without somewhere to be, and nothing
/// else in the app has any business knowing that. So this is deliberately the
/// smallest possible version of location: permission is asked for the moment
/// the feature is used and not before, a single fix is taken, it's turned into
/// a place *name* on the device, and the coordinates are dropped. Nothing is
/// written to disk, no location history is kept, and the only thing that
/// leaves the device is a neighbourhood — "Ballard, Seattle" — not a position.
@MainActor
final class PlaceLocator: NSObject, ObservableObject {
    static let shared = PlaceLocator()

    enum Failure: LocalizedError {
        case denied
        case unavailable
        case noPlaceName

        var errorDescription: String? {
            switch self {
            case .denied:
                return "Location is off for Steady, so it can't tell what's near you. Turn it on in iOS Settings → Privacy → Location Services → Steady, or use the at-home ideas instead."
            case .unavailable:
                return "Couldn't get a location just now. Try again in a moment, or use the at-home ideas instead."
            case .noPlaceName:
                return "Couldn't work out what neighbourhood that is. Try again in a moment, or use the at-home ideas instead."
            }
        }
    }

    private let manager = CLLocationManager()
    private var fix: CheckedContinuation<CLLocation, Error>?
    private var permissionWaiters: [CheckedContinuation<Void, Never>] = []

    private override init() {
        super.init()
        manager.delegate = self
        // Neighbourhood accuracy is all a restaurant search needs, and it's
        // the cheapest fix to get.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }
    var isDenied: Bool { status == .denied || status == .restricted }
    /// True before iOS has ever asked — the tap that uses the feature is what
    /// should trigger the prompt.
    var needsPermission: Bool { status == .notDetermined }

    /// A place name and nothing else. Throws rather than guessing.
    func nearbyPlaceName() async throws -> String {
        if needsPermission {
            manager.requestWhenInUseAuthorization()
            await waitForPermission()
        }
        guard !isDenied else { throw Failure.denied }

        let location = try await currentFix()
        defer { manager.stopUpdatingLocation() }

        // CLGeocoder, not MapKit's newer request type: that one is iOS 26 and
        // this app runs back to 18. The deprecation warning is expected.
        let places = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let mark = places?.first else { throw Failure.noPlaceName }
        let parts = [mark.subLocality, mark.locality, mark.administrativeArea]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        // Drop a repeated name ("Seattle, Seattle") without dropping a real
        // neighbourhood inside a city.
        var seen = Set<String>()
        let unique = parts.filter { seen.insert($0.lowercased()).inserted }
        guard !unique.isEmpty else { throw Failure.noPlaceName }
        return unique.prefix(2).joined(separator: ", ")
    }

    private func currentFix() async throws -> CLLocation {
        // A fix from the last few minutes is the same neighbourhood; no point
        // waking the radio for it.
        if let cached = manager.location,
           Date().timeIntervalSince(cached.timestamp) < 5 * 60 {
            return cached
        }
        return try await withCheckedThrowingContinuation { continuation in
            guard fix == nil else {
                continuation.resume(throwing: Failure.unavailable)
                return
            }
            fix = continuation
            manager.requestLocation()
        }
    }

    private func waitForPermission() async {
        await withCheckedContinuation { continuation in
            permissionWaiters.append(continuation)
        }
    }

    private func resolvePermissionWaiters() {
        let waiting = permissionWaiters
        permissionWaiters = []
        waiting.forEach { $0.resume() }
    }

    private func finishFix(with result: Result<CLLocation, Error>) {
        guard let continuation = fix else { return }
        fix = nil
        continuation.resume(with: result)
    }
}

extension PlaceLocator: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard manager.authorizationStatus != .notDetermined else { return }
            resolvePermissionWaiters()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if let location = locations.last {
                finishFix(with: .success(location))
            } else {
                finishFix(with: .failure(Failure.unavailable))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in
            finishFix(with: .failure(error))
        }
    }
}
