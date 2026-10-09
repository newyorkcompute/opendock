import Foundation

/// How far back a price chart reaches. The raw values are what the quote source calls them.
public enum StockChartRange: String, CaseIterable, Codable, Sendable, Identifiable {
    case oneDay = "1d"
    case fiveDays = "5d"
    case oneMonth = "1mo"
    case sixMonths = "6mo"
    case oneYear = "1y"

    public var id: String { rawValue }

    /// The tab label.
    public var title: String {
        switch self {
        case .oneDay: "1D"
        case .fiveDays: "5D"
        case .oneMonth: "1M"
        case .sixMonths: "6M"
        case .oneYear: "1Y"
        }
    }

    /// "today", "the last 5 days", for captions.
    public var description: String {
        switch self {
        case .oneDay: "today"
        case .fiveDays: "the last 5 days"
        case .oneMonth: "the last month"
        case .sixMonths: "the last 6 months"
        case .oneYear: "the last year"
        }
    }
}

/// One point on a price chart.
public struct StockChartPoint: Hashable, Codable, Sendable {
    public var time: Date
    public var close: Double

    public init(time: Date, close: Double) {
        self.time = time
        self.close = close
    }
}

/// Closing prices over a range, with the close before the range started as the baseline.
public struct StockChart: Hashable, Codable, Sendable {
    public var symbol: String
    public var range: StockChartRange
    /// Oldest first. Empty when the market hasn't traded in the range yet.
    public var points: [StockChartPoint]
    /// The close just before `points` begin, if the source gave one.
    public var previousClose: Double?
    public var fetchedAt: Date

    public init(
        symbol: String, range: StockChartRange, points: [StockChartPoint], previousClose: Double?, fetchedAt: Date
    ) {
        self.symbol = symbol
        self.range = range
        self.points = points
        self.previousClose = previousClose
        self.fetchedAt = fetchedAt
    }

    public var closes: [Double] { points.map(\.close) }
    public var low: Double? { closes.min() }
    public var high: Double? { closes.max() }

    /// Last close minus the baseline (or the first point, without one).
    public var change: Double? {
        guard let last = points.last?.close, let start = previousClose ?? points.first?.close else { return nil }
        return last - start
    }

    /// `change` as a fraction of the baseline, e.g. 0.012 for +1.2%.
    public var changeFraction: Double? {
        guard let change, let start = previousClose ?? points.first?.close, start != 0 else { return nil }
        return change / start
    }
}

/// Which way a price moved, for colors.
public enum StockMove: Sendable {
    case up
    case down
    case flat

    public init(change: Double?) {
        guard let change, change != 0 else {
            self = .flat
            return
        }
        self = change > 0 ? .up : .down
    }
}

/// The latest price for one symbol and the day's move.
public struct StockQuote: Hashable, Codable, Sendable {
    public var symbol: String
    /// The company or index name, e.g. "Apple Inc." or "S&P 500". Falls back to the symbol.
    public var name: String
    /// ISO 4217 code such as "USD", or the source's own code ("GBp" for pence).
    public var currency: String
    /// The exchange's display name, e.g. "NasdaqGS".
    public var exchange: String?
    public var price: Double
    /// The regular session's close on the previous trading day.
    public var previousClose: Double
    /// Decimals the source recommends for the price (2 for most stocks, 4 for currencies).
    public var fractionDigits: Int
    /// When `price` was last traded.
    public var marketTime: Date
    /// Today's regular trading session, when the source said.
    public var regularSession: DateInterval?
    /// The exchange's time zone, for session times.
    public var timeZoneIdentifier: String?
    public var fetchedAt: Date

    public init(
        symbol: String, name: String, currency: String, exchange: String? = nil, price: Double, previousClose: Double,
        fractionDigits: Int = 2, marketTime: Date, regularSession: DateInterval? = nil,
        timeZoneIdentifier: String? = nil, fetchedAt: Date
    ) {
        self.symbol = symbol
        self.name = name
        self.currency = currency
        self.exchange = exchange
        self.price = price
        self.previousClose = previousClose
        self.fractionDigits = fractionDigits
        self.marketTime = marketTime
        self.regularSession = regularSession
        self.timeZoneIdentifier = timeZoneIdentifier
        self.fetchedAt = fetchedAt
    }

    /// Today's move in the stock's currency.
    public var change: Double { price - previousClose }

    /// Today's move as a fraction of the previous close, or nil when that was zero.
    public var changeFraction: Double? {
        previousClose != 0 ? change / previousClose : nil
    }

    public var move: StockMove { StockMove(change: change) }

    /// True while the regular session is in progress. Without session times, true when the
    /// last trade is less than 20 minutes old (delayed feeds trail the market by 15).
    public func isMarketOpen(at now: Date) -> Bool {
        if let regularSession { return regularSession.contains(now) }
        return now.timeIntervalSince(marketTime) < 20 * 60
    }

    public var timeZone: TimeZone? { timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) }
}

/// A quote and the chart that came with it.
public struct StockSeries: Hashable, Codable, Sendable {
    /// Nil when the response couldn't say what the previous close was.
    public var quote: StockQuote?
    public var chart: StockChart

    public init(quote: StockQuote?, chart: StockChart) {
        self.quote = quote
        self.chart = chart
    }
}

/// A match from symbol search.
public struct StockSearchResult: Hashable, Sendable, Identifiable {
    public var id: String { symbol }
    public var symbol: String
    public var name: String
    /// The exchange's short display name, e.g. "NASDAQ".
    public var exchange: String?
    /// "Equity", "ETF", "Index", "Currency", ...
    public var kind: String?

    public init(symbol: String, name: String, exchange: String? = nil, kind: String? = nil) {
        self.symbol = symbol
        self.name = name
        self.exchange = exchange
        self.kind = kind
    }

    /// "Apple Inc. · NASDAQ · Equity", with whatever is known.
    public var detail: String {
        [exchange, kind].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - Symbols

/// Parses and writes the comma-separated watchlist a stocks tile stores in its `symbols`
/// setting. Lives here rather than in the widget so it can be unit tested.
public enum StockSymbols {
    /// Enough for a dock tile; also keeps the once-a-minute refresh from flooding the source.
    public static let maximumCount = 20
    /// Yahoo's longest symbols ("BRK-B", "EURUSD=X", "^DJI", "BTC-USD") fit comfortably.
    public static let maximumLength = 16

    private static let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-^=")

    /// Upper-cases, drops characters a ticker can't contain, removes blanks and duplicates,
    /// and keeps the first `maximumCount`.
    public static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        var symbols: [String] = []
        for piece in text.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline }) {
            guard let symbol = sanitize(String(piece)), seen.insert(symbol).inserted else { continue }
            symbols.append(symbol)
            if symbols.count == maximumCount { break }
        }
        return symbols
    }

    /// One symbol as typed: trimmed, upper-cased, invalid characters removed. Nil when
    /// nothing valid is left or it's too long.
    public static func sanitize(_ text: String) -> String? {
        let symbol = String(text.uppercased().filter { allowed.contains($0) })
        guard !symbol.isEmpty, symbol.count <= maximumLength,
            symbol.contains(where: \.isLetter) || symbol.contains(where: \.isNumber)
        else { return nil }
        return symbol
    }

    /// The setting value for `symbols`: "AAPL, MSFT".
    public static func storageValue(_ symbols: [String]) -> String {
        symbols.joined(separator: ", ")
    }
}

// MARK: - Formatting

/// Text for prices and moves. Every function takes a locale so tests are deterministic.
public enum StockFormatting {
    /// "$229.04", "€12.50", "1,234.5 GBp". Codes that aren't ISO 4217 are shown after the number.
    public static func price(_ value: Double, currency: String, fractionDigits: Int = 2, locale: Locale = .current)
        -> String
    {
        let digits = max(0, min(fractionDigits, 4))
        if isISOCurrencyCode(currency) {
            return value.formatted(.currency(code: currency).precision(.fractionLength(digits)).locale(locale))
        }
        let number = value.formatted(.number.precision(.fractionLength(digits)).locale(locale))
        return currency.isEmpty ? number : "\(number) \(currency)"
    }

    /// "+1.23", "-0.45", "0.00": the move in the currency, always signed unless zero.
    public static func change(_ value: Double, fractionDigits: Int = 2, locale: Locale = .current) -> String {
        let digits = max(0, min(fractionDigits, 4))
        return value.formatted(
            .number.precision(.fractionLength(digits)).sign(strategy: .always(includingZero: false)).locale(locale))
    }

    /// "+0.54%", "-1.20%", "0.00%" from a fraction such as 0.0054. "—" when there's no baseline.
    public static func percent(_ fraction: Double?, locale: Locale = .current) -> String {
        guard let fraction, fraction.isFinite else { return "—" }
        return fraction.formatted(
            .percent.precision(.fractionLength(2)).sign(strategy: .always(includingZero: false)).locale(locale))
    }

    /// "+1.23 (+0.54%)" for popovers.
    public static func changeWithPercent(
        _ value: Double, fraction: Double?, fractionDigits: Int = 2, locale: Locale = .current
    ) -> String {
        "\(change(value, fractionDigits: fractionDigits, locale: locale)) (\(percent(fraction, locale: locale)))"
    }

    private static func isISOCurrencyCode(_ code: String) -> Bool {
        code.count == 3 && code.allSatisfy { $0.isUppercase && $0.isLetter }
    }
}

// MARK: - Chart geometry

/// Closes scaled to 0...1 for drawing, with the baseline on the same scale, so the tile and
/// popover draw the same thing at different sizes.
public struct StockChartLayout: Equatable, Sendable {
    /// One per close, 0 at the lowest price in view and 1 at the highest.
    public var values: [Double]
    /// One per close, 0 at the left edge and 1 at the right.
    public var positions: [Double]
    /// Where the previous close falls on the `values` scale, when there is one.
    public var baseline: Double?

    public init(values: [Double], positions: [Double]? = nil, baseline: Double?) {
        self.values = values
        self.positions = positions ?? Self.evenPositions(count: values.count)
        self.baseline = baseline
    }

    /// Scales `closes` and `previousClose` together, so the baseline is in view, and
    /// spaces the points evenly. A flat series sits in the middle.
    public static func make(closes: [Double], previousClose: Double?) -> StockChartLayout {
        guard !closes.isEmpty else { return StockChartLayout(values: [], baseline: nil) }
        var low = closes.min() ?? 0
        var high = closes.max() ?? 0
        if let previousClose {
            low = min(low, previousClose)
            high = max(high, previousClose)
        }
        let span = high - low
        guard span > 0 else {
            return StockChartLayout(values: closes.map { _ in 0.5 }, baseline: previousClose.map { _ in 0.5 })
        }
        return StockChartLayout(
            values: closes.map { ($0 - low) / span },
            baseline: previousClose.map { ($0 - low) / span })
    }

    /// The layout for `chart`. A one-day chart is spread over the trading `session`, so a
    /// half-finished day fills half the width, as long as the points fall inside it.
    public static func make(chart: StockChart, session: DateInterval?) -> StockChartLayout {
        var layout = make(closes: chart.closes, previousClose: chart.previousClose)
        guard chart.range == .oneDay, let session, session.duration > 0,
            let first = chart.points.first?.time, session.contains(first)
        else { return layout }
        layout.positions = chart.points.map {
            min(1, max(0, $0.time.timeIntervalSince(session.start) / session.duration))
        }
        return layout
    }

    static func evenPositions(count: Int) -> [Double] {
        guard count > 1 else { return count == 1 ? [0] : [] }
        return (0 ..< count).map { Double($0) / Double(count - 1) }
    }
}
