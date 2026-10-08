import Foundation
import Observation
import os

/// What's wrong when a feed has no fresh weather. The tile shows `shortDescription`; the
/// popover shows `description`.
public enum WeatherFeedError: Equatable, Sendable {
    /// The request couldn't reach Open-Meteo.
    case offline
    /// Open-Meteo answered with an error.
    case server(String?)
    /// Location Services hasn't been asked yet, and the widget may not ask on its own right now.
    case locationNotDetermined
    case locationDenied
    /// Authorized, but no fix was available.
    case locationUnavailable

    public var shortDescription: String {
        switch self {
        case .offline: "Offline"
        case .server: "Unavailable"
        case .locationNotDetermined: "Tap to allow"
        case .locationDenied: "No location"
        case .locationUnavailable: "No location"
        }
    }

    public var description: String {
        switch self {
        case .offline:
            "OpenDock can't reach Open-Meteo right now. Check your internet connection."
        case .server(let reason):
            reason.map { "Open-Meteo returned an error: \($0)" } ?? "Open-Meteo returned an error."
        case .locationNotDetermined:
            "Allow location access, or pick a city in this widget's settings."
        case .locationDenied:
            "Location access is turned off. Enable it in System Settings › Privacy & Security › Location Services, "
                + "or pick a city in this widget's settings."
        case .locationUnavailable:
            "Your location couldn't be determined. Pick a city in this widget's settings to show its weather instead."
        }
    }
}

/// Owns one `WeatherFeed` per location so tiles and popovers showing the same place share a
/// report and a request, and fronts Location Services and city search for them.
///
/// Use ``shared`` in the app; tests build one with fakes.
@MainActor
@Observable
public final class WeatherService {
    /// Process-wide instance backed by Open-Meteo, Location Services, and the on-disk cache.
    public static let shared = WeatherService(
        provider: OpenMeteoClient(),
        locationSource: CoreLocationWeatherSource(),
        cache: FileWeatherReportCache()
    )

    /// How old a report may get before the next refresh.
    public static let refreshInterval: Duration = .seconds(15 * 60)
    /// How long to wait after a failed refresh before trying again.
    public static let retryInterval: Duration = .seconds(60)

    /// Current Location Services authorization, kept up to date after every prompt and fix.
    public private(set) var locationAuthorization: WeatherLocationAuthorization

    @ObservationIgnored let provider: any WeatherProvider
    @ObservationIgnored let locationSource: any WeatherLocationSource
    @ObservationIgnored let cache: any WeatherReportCache
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored private var feeds: [String: WeatherFeed] = [:]

    public init(
        provider: any WeatherProvider,
        locationSource: any WeatherLocationSource,
        cache: any WeatherReportCache,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.locationSource = locationSource
        self.cache = cache
        self.now = now
        locationAuthorization = locationSource.authorization
    }

    /// The feed for `location`, created on first use and seeded from the cache.
    public func feed(for location: WeatherLocation) -> WeatherFeed {
        if let feed = feeds[location.key] { return feed }
        let feed = WeatherFeed(location: location, service: self)
        feeds[location.key] = feed
        return feed
    }

    /// Shows the Location Services prompt if the user hasn't decided yet.
    public func requestLocationAccess() async {
        locationAuthorization = await locationSource.requestAuthorization()
    }

    /// Re-reads the authorization, for when the user may have changed it in System Settings.
    public func refreshLocationAuthorization() {
        locationAuthorization = locationSource.authorization
    }

    /// Cities matching `query`, best match first. Empty for queries under two characters.
    public func searchPlaces(_ query: String) async throws -> [WeatherPlace] {
        try await provider.searchPlaces(named: query)
    }

    /// The Mac's location, prompting first if needed. Updates `locationAuthorization` either way.
    func currentPlace() async throws -> WeatherPlace {
        defer { locationAuthorization = locationSource.authorization }
        return try await locationSource.currentPlace()
    }
}

/// The weather for one location: the latest report, whether it's being refreshed, and what
/// went wrong if it couldn't be. Get one from `WeatherService.feed(for:)`.
@MainActor
@Observable
public final class WeatherFeed {
    public let location: WeatherLocation
    /// The most recent report, possibly from the cache and possibly old. Check ``isStale(at:)``.
    public private(set) var report: WeatherReport?
    /// Why the last refresh failed, or nil after a success.
    public private(set) var error: WeatherFeedError?
    public private(set) var isRefreshing = false

    @ObservationIgnored private unowned let service: WeatherService
    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    private let log = Logger(subsystem: "com.newyorkcompute.opendock", category: "Weather")

    init(location: WeatherLocation, service: WeatherService) {
        self.location = location
        self.service = service
        report = service.cache.report(forKey: location.key)
    }

    /// True once the report is older than two refresh intervals, so a tile can say so.
    public func isStale(at now: Date) -> Bool {
        guard let report else { return false }
        return now.timeIntervalSince(report.fetchedAt) > 2 * WeatherService.refreshInterval.seconds
    }

    /// True when the report is older than the refresh interval, or a failed attempt is old enough to retry.
    public func isDue(at now: Date) -> Bool {
        if error != nil || report == nil {
            guard let lastAttempt else { return true }
            return now.timeIntervalSince(lastAttempt) >= WeatherService.retryInterval.seconds
        }
        guard let report else { return true }
        return now.timeIntervalSince(report.fetchedAt) >= WeatherService.refreshInterval.seconds
    }

    /// Fetches new weather if it's due (or `force` is set). Concurrent callers share one request.
    ///
    /// For the current location, `mayPrompt: false` skips the fetch while Location Services
    /// hasn't been asked yet, leaving ``error`` as `locationNotDetermined`, so a tile that
    /// appears on a fresh install doesn't prompt behind the welcome window.
    public func refresh(force: Bool = false, mayPrompt: Bool = true) async {
        if let inFlight {
            await inFlight.value
            return
        }
        guard force || isDue(at: service.now()) else { return }
        if location == .current, !mayPrompt, service.locationAuthorization == .notDetermined {
            error = .locationNotDetermined
            return
        }
        let task = Task { await performRefresh() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    /// Refreshes when due, then sleeps until the next one, until the surrounding task is
    /// cancelled. Run it from a view's `.task(id:)` while the dock is visible.
    public func autoRefresh(mayPrompt: Bool = true) async {
        while !Task.isCancelled {
            await refresh(mayPrompt: mayPrompt)
            try? await Task.sleep(for: nextRefreshDelay(at: service.now()))
        }
    }

    /// How long until the next refresh is due, at least a few seconds.
    func nextRefreshDelay(at now: Date) -> Duration {
        let floor: Duration = .seconds(5)
        if error != nil || report == nil {
            guard let lastAttempt else { return floor }
            let elapsed = now.timeIntervalSince(lastAttempt)
            return max(floor, WeatherService.retryInterval - .seconds(elapsed))
        }
        guard let report else { return floor }
        let elapsed = now.timeIntervalSince(report.fetchedAt)
        return max(floor, WeatherService.refreshInterval - .seconds(elapsed))
    }

    private func performRefresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        lastAttempt = service.now()

        do {
            let place: WeatherPlace
            switch location {
            case .place(let chosen): place = chosen
            case .current: place = try await service.currentPlace()
            }
            var fresh = try await service.provider.forecast(latitude: place.latitude, longitude: place.longitude)
            fresh.place = place
            report = fresh
            error = nil
            service.cache.store(fresh, forKey: location.key)
        } catch is CancellationError {
            return
        } catch let failure as WeatherLocationError {
            self.error = failure == .denied ? .locationDenied : .locationUnavailable
        } catch let failure as WeatherError {
            switch failure {
            case .offline: self.error = .offline
            case .server(_, let reason): self.error = .server(reason)
            case .badResponse: self.error = .server("The response couldn't be read.")
            }
            log.error(
                "Weather refresh failed for \(self.location.key, privacy: .public): \(String(describing: failure), privacy: .public)"
            )
        } catch {
            self.error = .server(error.localizedDescription)
            log.error(
                "Weather refresh failed for \(self.location.key, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

extension Duration {
    /// The duration in seconds, as a `TimeInterval`.
    fileprivate var seconds: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
