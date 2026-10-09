import Foundation
import Observation

/// Where `NetworkActivityMonitor` gets its raw readings. The app uses
/// ``HostNetworkActivitySource``; tests substitute scripted values.
public protocol NetworkActivitySource: Sendable {
    /// Every interface the kernel lists, with its cumulative counters. Empty on failure.
    func interfaces() -> [NetworkInterfaceReading]
    /// How the system describes interfaces, by BSD name. Called only when the set of
    /// interfaces changes, so it may be slower than `interfaces()`.
    func descriptions() -> [String: NetworkInterfaceDescription]
}

/// Samples the network interfaces on demand and keeps the latest ``snapshot`` and a short
/// ``history`` of per-interface rates for sparklines.
///
/// Nothing runs on its own: tiles drive it with ``autoRefresh(every:)`` from a `.task`
/// that is only alive while the dock is visible, so a hidden dock costs no CPU. Use
/// ``shared`` so every tile reads the same data and the interfaces are read once a second.
@MainActor
@Observable
public final class NetworkActivityMonitor {
    /// Process-wide instance shared by all network tiles.
    public static let shared = NetworkActivityMonitor()

    /// How often tiles ask for a new reading.
    public nonisolated static let defaultInterval: Duration = .seconds(1)
    /// A minute of history at the default interval.
    public nonisolated static let defaultHistoryLength = 60

    public private(set) var snapshot = NetworkActivitySnapshot()
    public private(set) var history: NetworkHistory

    @ObservationIgnored private let source: any NetworkActivitySource
    @ObservationIgnored private var previousReadings: [NetworkInterfaceReading] = []
    @ObservationIgnored private var previousInstant: ContinuousClock.Instant?
    @ObservationIgnored private var lastRefresh: ContinuousClock.Instant?
    @ObservationIgnored private var descriptions: [String: NetworkInterfaceDescription] = [:]
    @ObservationIgnored private var describedNames: Set<String>?

    public init(
        source: any NetworkActivitySource = HostNetworkActivitySource(),
        historyLength: Int = NetworkActivityMonitor.defaultHistoryLength,
        now: ContinuousClock.Instant = ContinuousClock().now
    ) {
        self.source = source
        history = NetworkHistory(capacity: historyLength)
        // Take the baseline now so the first refresh has something to diff against.
        previousReadings = source.interfaces()
        previousInstant = previousReadings.isEmpty ? nil : now
    }

    /// Whether at least one interface has a rate yet.
    public var hasReading: Bool { snapshot.interfaces.contains { $0.throughput != nil } }

    // MARK: Refresh

    /// Takes a new reading now. Rates cover the time since the previous call, so two calls
    /// in quick succession produce a noisy figure; prefer ``autoRefresh(every:)``.
    /// `now` is injectable so tests can control the elapsed time.
    public func refresh(now: ContinuousClock.Instant = ContinuousClock().now) {
        lastRefresh = now
        let readings = source.interfaces()

        var rates: [String: NetworkThroughput] = [:]
        if let previousInstant {
            let elapsed = Self.seconds(now - previousInstant)
            rates = NetworkThroughput.perInterface(from: previousReadings, to: readings, elapsed: elapsed)
        }
        if !readings.isEmpty {
            previousReadings = readings
            previousInstant = now
        }

        refreshDescriptionsIfNeeded(for: readings)
        let lastRates = Dictionary(
            snapshot.interfaces.compactMap { status in status.throughput.map { (status.name, $0) } },
            uniquingKeysWith: { first, _ in first })
        let interfaces = readings.map { reading -> NetworkInterfaceStatus in
            var refined = reading
            let description = descriptions[reading.name]
            if let kind = description?.kind { refined.kind = kind }
            // No elapsed time means no new information, so the last rate stands.
            return NetworkInterfaceStatus(
                reading: refined,
                displayName: description?.displayName,
                throughput: rates[reading.name] ?? lastRates[reading.name])
        }

        // Assigning an equal snapshot would still redraw every tile that reads it.
        let newSnapshot = NetworkActivitySnapshot(interfaces: interfaces)
        if newSnapshot != snapshot { snapshot = newSnapshot }
        if !rates.isEmpty { history.append(rates) }
    }

    /// Refreshes only if the last reading is older than three quarters of `interval`, so
    /// several tiles sharing the monitor don't each read the interfaces.
    public func refreshIfStale(
        interval: Duration = NetworkActivityMonitor.defaultInterval,
        now: ContinuousClock.Instant = ContinuousClock().now
    ) {
        if let lastRefresh, now - lastRefresh < interval * 0.75 { return }
        refresh(now: now)
    }

    /// Samples every `interval` until the surrounding task is cancelled. Run it from a
    /// view's `.task(id:)` keyed on `dockIsVisible` so sampling stops with the dock.
    public func autoRefresh(every interval: Duration = NetworkActivityMonitor.defaultInterval) async {
        refreshIfStale(interval: interval)
        if !hasReading {
            // Baseline only: wait a moment so the first figure covers real time.
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            refresh()
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            if Task.isCancelled { return }
            refreshIfStale(interval: interval)
        }
    }

    // MARK: Descriptions

    /// Asks the system about the interfaces again only when the set of names changes,
    /// which is rare (plugging in an adapter, joining a VPN).
    private func refreshDescriptionsIfNeeded(for readings: [NetworkInterfaceReading]) {
        let names = Set(readings.map(\.name))
        guard names != describedNames else { return }
        describedNames = names
        descriptions = source.descriptions()
    }

    nonisolated static func seconds(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
