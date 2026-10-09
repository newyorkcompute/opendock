import Foundation
import Observation
import os

/// What's wrong when a feed has no fresh quote. The tile shows `shortDescription`; the
/// popover shows `description`.
public enum StockFeedError: Equatable, Sendable {
    /// The request couldn't reach the quote source.
    case offline
    /// The source doesn't know the symbol.
    case unknownSymbol
    /// The source answered with an error.
    case server(String?)

    public var shortDescription: String {
        switch self {
        case .offline: "Offline"
        case .unknownSymbol: "Not found"
        case .server: "Unavailable"
        }
    }

    public var description: String {
        switch self {
        case .offline:
            "OpenDock can't reach Yahoo Finance right now. Check your internet connection."
        case .unknownSymbol:
            "Yahoo Finance doesn't know this symbol. Check it in this widget's settings."
        case .server(let reason):
            reason.map { "Yahoo Finance returned an error: \($0)" } ?? "Yahoo Finance returned an error."
        }
    }
}

/// Owns one `StockFeed` per symbol so tiles and popovers watching the same symbol share a
/// quote and a request, and fronts symbol search for them.
///
/// Use ``shared`` in the app; tests build one with fakes.
@MainActor
@Observable
public final class StocksService {
    /// Process-wide instance backed by Yahoo Finance and the on-disk cache.
    public static let shared = StocksService(provider: YahooFinanceClient(), cache: FileStockCache())

    /// A symbol is never fetched more often than this, whatever a tile asks for.
    public static let minimumRefreshInterval: Duration = .seconds(60)
    /// How long to wait after a failed refresh before trying again.
    public static let retryInterval: Duration = .seconds(60)
    /// How old a chart other than today's may get before the popover fetches it again.
    public static let chartRefreshInterval: Duration = .seconds(5 * 60)

    @ObservationIgnored let provider: any StockQuoteProvider
    @ObservationIgnored let cache: any StockCache
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored private var feeds: [String: StockFeed] = [:]

    public init(
        provider: any StockQuoteProvider, cache: any StockCache, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.cache = cache
        self.now = now
    }

    /// The feed for `symbol`, created on first use and seeded from the cache.
    public func feed(for symbol: String) -> StockFeed {
        if let feed = feeds[symbol] { return feed }
        let feed = StockFeed(symbol: symbol, service: self)
        feeds[symbol] = feed
        return feed
    }

    /// Symbols matching `query`, best match first. Empty for a blank query.
    public func search(_ query: String) async throws -> [StockSearchResult] {
        try await provider.search(query)
    }

    /// Refreshes today's quote for every symbol that's due, all at once.
    public func refresh(_ symbols: [String], maxAge: Duration, force: Bool = false) async {
        let feeds = symbols.map(feed(for:))
        await withTaskGroup(of: Void.self) { group in
            for feed in feeds {
                group.addTask { await feed.refresh(maxAge: maxAge, force: force) }
            }
        }
    }

    /// Refreshes the symbols that are due, then sleeps until the next one is, until the
    /// surrounding task is cancelled. Run it from a view's `.task(id:)` while the dock is
    /// visible, so a hidden dock fetches nothing.
    public func autoRefresh(_ symbols: [String], every interval: Duration) async {
        while !Task.isCancelled {
            await refresh(symbols, maxAge: interval)
            try? await Task.sleep(for: nextRefreshDelay(for: symbols, maxAge: interval, at: now()))
        }
    }

    /// How long until the first of `symbols` is due again, at least a few seconds.
    public func nextRefreshDelay(for symbols: [String], maxAge: Duration, at now: Date) -> Duration {
        symbols.map { feed(for: $0).nextRefreshDelay(maxAge: maxAge, at: now) }.min() ?? max(maxAge, .seconds(5))
    }
}

/// The quote and charts for one symbol: the latest price, whether it's being refreshed,
/// and what went wrong if it couldn't be. Get one from `StocksService.feed(for:)`.
@MainActor
@Observable
public final class StockFeed {
    public let symbol: String
    /// The most recent quote, possibly from the cache and possibly old. Check ``isStale(maxAge:at:)``.
    public private(set) var quote: StockQuote?
    /// Why the last refresh failed, or nil after a success.
    public private(set) var error: StockFeedError?
    public private(set) var isRefreshing = false
    private var charts: [StockChartRange: StockChart] = [:]

    @ObservationIgnored private unowned let service: StocksService
    @ObservationIgnored private var lastAttempts: [StockChartRange: Date] = [:]
    @ObservationIgnored private var inFlight: [StockChartRange: Task<Void, Never>] = [:]
    private let log = Logger(subsystem: "com.newyorkcompute.opendock", category: "Stocks")

    init(symbol: String, service: StocksService) {
        self.symbol = symbol
        self.service = service
        for range in StockChartRange.allCases {
            guard let cached = service.cache.series(forKey: Self.cacheKey(symbol: symbol, range: range)) else {
                continue
            }
            charts[range] = cached.chart
            if let cachedQuote = cached.quote, quote.map({ $0.fetchedAt < cachedQuote.fetchedAt }) ?? true {
                quote = cachedQuote
            }
        }
    }

    static func cacheKey(symbol: String, range: StockChartRange) -> String {
        "\(symbol)-\(range.rawValue)"
    }

    /// The chart for `range`, if it has been fetched or cached.
    public func chart(for range: StockChartRange) -> StockChart? {
        charts[range]
    }

    /// True once the quote is older than two refresh intervals, so a tile can say so.
    public func isStale(maxAge: Duration, at now: Date) -> Bool {
        guard let quote else { return false }
        let limit = 2 * max(maxAge, StocksService.minimumRefreshInterval).timeInterval
        return now.timeIntervalSince(quote.fetchedAt) > limit
    }

    /// True when the data for `range` is older than `maxAge`, or a failed attempt is old
    /// enough to retry.
    public func isDue(range: StockChartRange = .oneDay, maxAge: Duration, at now: Date) -> Bool {
        let chart = charts[range]
        if error != nil || chart == nil || (range == .oneDay && quote == nil) {
            guard let lastAttempt = lastAttempts[range] else { return true }
            return now.timeIntervalSince(lastAttempt) >= StocksService.retryInterval.timeInterval
        }
        guard let chart else { return true }
        return now.timeIntervalSince(chart.fetchedAt) >= maxAge.timeInterval
    }

    /// Fetches `range` if it's due, or `force` is set and the last attempt is at least a
    /// minute old. Concurrent callers share one request. `maxAge` is raised to
    /// `StocksService.minimumRefreshInterval` when it's shorter.
    public func refresh(
        range: StockChartRange = .oneDay, maxAge: Duration = StocksService.minimumRefreshInterval,
        force: Bool = false
    ) async {
        if let inFlight = inFlight[range] {
            await inFlight.value
            return
        }
        let now = service.now()
        if force {
            guard canForceRefresh(range: range, at: now) else { return }
        } else {
            guard isDue(range: range, maxAge: max(maxAge, StocksService.minimumRefreshInterval), at: now) else {
                return
            }
        }
        let task = Task { await performRefresh(range: range) }
        inFlight[range] = task
        await task.value
        inFlight[range] = nil
    }

    /// Whether a Refresh button should do anything: no attempt for `range` in the last minute.
    public func canForceRefresh(range: StockChartRange = .oneDay, at now: Date) -> Bool {
        guard let lastAttempt = lastAttempts[range] else { return true }
        return now.timeIntervalSince(lastAttempt) >= StocksService.minimumRefreshInterval.timeInterval
    }

    /// How long until today's quote is due again, at least a few seconds.
    public func nextRefreshDelay(maxAge: Duration, at now: Date) -> Duration {
        let floor: Duration = .seconds(5)
        let maxAge = max(maxAge, StocksService.minimumRefreshInterval)
        if error != nil || quote == nil || charts[.oneDay] == nil {
            guard let lastAttempt = lastAttempts[.oneDay] else { return floor }
            let elapsed = now.timeIntervalSince(lastAttempt)
            return max(floor, StocksService.retryInterval - .seconds(elapsed))
        }
        guard let chart = charts[.oneDay] else { return floor }
        let elapsed = now.timeIntervalSince(chart.fetchedAt)
        return max(floor, maxAge - .seconds(elapsed))
    }

    private func performRefresh(range: StockChartRange) async {
        isRefreshing = true
        defer { isRefreshing = false }
        lastAttempts[range] = service.now()

        do {
            let series = try await service.provider.series(for: symbol, range: range)
            charts[range] = series.chart
            if let fresh = series.quote { quote = fresh }
            error = nil
            service.cache.store(series, forKey: Self.cacheKey(symbol: symbol, range: range))
        } catch is CancellationError {
            return
        } catch let failure as StockError {
            switch failure {
            case .offline: error = .offline
            case .unknownSymbol: error = .unknownSymbol
            case .server(_, let reason): error = .server(reason)
            case .badResponse: error = .server("The response couldn't be read.")
            }
            log.error(
                "Quote refresh failed for \(self.symbol, privacy: .public): \(String(describing: failure), privacy: .public)"
            )
        } catch {
            self.error = .server(error.localizedDescription)
            log.error(
                "Quote refresh failed for \(self.symbol, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

extension Duration {
    /// The duration in seconds, as a `TimeInterval`.
    fileprivate var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
