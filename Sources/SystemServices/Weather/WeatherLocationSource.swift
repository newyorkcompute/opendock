import CoreLocation
import Foundation
import os

/// Whether OpenDock may use Location Services.
public enum WeatherLocationAuthorization: Sendable, Equatable {
    /// The user hasn't been asked yet.
    case notDetermined
    /// Refused, restricted, or Location Services is off.
    case denied
    case authorized
}

/// Why the Mac's location couldn't be found.
public enum WeatherLocationError: Error, Equatable, Sendable {
    case denied
    /// Authorized, but Location Services couldn't produce a fix.
    case unavailable
}

/// Where the "current location" comes from. `CoreLocationWeatherSource` asks Location
/// Services; tests use a fake.
@MainActor
public protocol WeatherLocationSource: AnyObject {
    var authorization: WeatherLocationAuthorization { get }
    /// Shows the system prompt if the user hasn't decided yet, and returns the outcome.
    func requestAuthorization() async -> WeatherLocationAuthorization
    /// The Mac's location, named when reverse geocoding works. Prompts first if needed.
    func currentPlace() async throws -> WeatherPlace
}

/// `CLLocationManager` behind `WeatherLocationSource`. One-shot fixes at kilometer accuracy
/// are all the weather needs, so this never keeps location updates running.
@MainActor
public final class CoreLocationWeatherSource: NSObject, WeatherLocationSource, CLLocationManagerDelegate {
    /// What to call the current location when reverse geocoding has no name for it.
    public static let fallbackName = "Current Location"

    public private(set) var authorization: WeatherLocationAuthorization
    private let manager: CLLocationManager
    private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []
    private var locationWaiters: [CheckedContinuation<(latitude: Double, longitude: Double), any Error>] = []
    private let log = Logger(subsystem: "com.newyorkcompute.opendock", category: "WeatherLocation")

    public override init() {
        let manager = CLLocationManager()
        self.manager = manager
        authorization = CoreLocationWeatherSource.authorization(for: manager.authorizationStatus)
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.delegate = self
    }

    public func requestAuthorization() async -> WeatherLocationAuthorization {
        guard authorization == .notDetermined else { return authorization }
        await withCheckedContinuation { continuation in
            authorizationWaiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
        return authorization
    }

    public func currentPlace() async throws -> WeatherPlace {
        if authorization == .notDetermined {
            _ = await requestAuthorization()
        }
        guard authorization == .authorized else { throw WeatherLocationError.denied }

        let fix = try await withCheckedThrowingContinuation { continuation in
            locationWaiters.append(continuation)
            // A request already in flight answers every waiter.
            if locationWaiters.count == 1 { manager.requestLocation() }
        }
        let name = await Self.placeName(latitude: fix.latitude, longitude: fix.longitude)
        return WeatherPlace(name: name ?? Self.fallbackName, latitude: fix.latitude, longitude: fix.longitude)
    }

    /// The nearest city or town, from Apple's reverse geocoder. Nil when it's unavailable.
    nonisolated private static func placeName(latitude: Double, longitude: Double) async -> String? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        let candidates = [
            placemark.locality, placemark.subAdministrativeArea, placemark.administrativeArea, placemark.name,
        ]
        return candidates.compactMap { $0 }.first { !$0.isEmpty }
    }

    private static func authorization(for status: CLAuthorizationStatus) -> WeatherLocationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: .authorized
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }

    // MARK: CLLocationManagerDelegate
    //
    // CoreLocation calls these on the thread that created the manager, which is the main
    // thread here, so hopping onto the main actor is an assertion rather than a dispatch.

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorization = Self.authorization(for: status)
            guard authorization != .notDetermined else { return }
            let waiters = authorizationWaiters
            authorizationWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        let fix = (latitude: coordinate.latitude, longitude: coordinate.longitude)
        MainActor.assumeIsolated {
            let waiters = locationWaiters
            locationWaiters.removeAll()
            waiters.forEach { $0.resume(returning: fix) }
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let code = (error as? CLError)?.code
        MainActor.assumeIsolated {
            log.error("Location request failed: \(error.localizedDescription, privacy: .public)")
            let failure: WeatherLocationError = code == .denied ? .denied : .unavailable
            let waiters = locationWaiters
            locationWaiters.removeAll()
            waiters.forEach { $0.resume(throwing: failure) }
        }
    }
}
