import Foundation

/// Where quotes and symbol search come from. `YahooFinanceClient` is the only implementation
/// in the app; tests use a fake. Keep everything Yahoo-specific behind this so the source
/// can be swapped when the endpoint changes.
public protocol StockQuoteProvider: Sendable {
    /// The latest quote for `symbol` and its chart over `range`.
    func series(for symbol: String, range: StockChartRange) async throws -> StockSeries
    /// Symbols matching a company name or ticker fragment, best match first.
    func search(_ query: String) async throws -> [StockSearchResult]
}

/// Why a quote request failed, in terms the widget can explain.
public enum StockError: Error, Equatable, Sendable {
    /// No network, a timeout, or the host couldn't be reached.
    case offline
    /// The source doesn't know the symbol.
    case unknownSymbol
    /// The source answered with an error (`reason` is its message when it sent one).
    case server(status: Int, reason: String?)
    /// The source's answer couldn't be read.
    case badResponse
}

/// Performs `request`. The default uses `URLSession`; tests return fixtures.
public typealias HTTPRequestLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

/// Yahoo Finance's public chart and search endpoints, the same JSON its website loads.
/// They need no key or account, but they're unofficial: Yahoo documents no terms for them,
/// has changed them before, and may rate-limit or block a client. Quotes are delayed
/// 15 minutes on most exchanges. The widget shows "Data from Yahoo Finance" wherever it
/// shows a quote, and treats a failure as "unavailable" rather than wrong.
public struct YahooFinanceClient: StockQuoteProvider {
    public static let chartEndpoint = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/")!
    public static let searchEndpoint = URL(string: "https://query2.finance.yahoo.com/v1/finance/search")!
    /// What to show as the data source.
    public static let attribution = "Data from Yahoo Finance"
    public static let attributionURL = URL(string: "https://finance.yahoo.com/")!
    /// Identifies the app honestly; Yahoo's chart endpoint serves non-browser agents.
    static let userAgent = "OpenDock/1.0 (macOS; +https://github.com/newyorkcompute/opendock)"

    private let loader: HTTPRequestLoader
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - loader: performs requests; defaults to a session with a 15-second timeout that fails
    ///     fast when offline instead of waiting for connectivity.
    ///   - now: the clock used for `fetchedAt`.
    public init(loader: HTTPRequestLoader? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.loader = loader ?? { request in try await Self.session.data(for: request) }
        self.now = now
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    // MARK: Requests

    /// Bar size per range: about 80 to 250 points each.
    static func interval(for range: StockChartRange) -> String {
        switch range {
        case .oneDay: "5m"
        case .fiveDays: "30m"
        case .oneMonth: "90m"
        case .sixMonths: "1d"
        case .oneYear: "1d"
        }
    }

    /// The chart request: regular-session closes over `range`, plus the quote in its `meta`.
    public static func chartURL(symbol: String, range: StockChartRange) -> URL {
        var components = URLComponents(url: chartEndpoint, resolvingAgainstBaseURL: false)!
        // `^GSPC` and `EURUSD=X` need percent-encoding in the path, which `path` does for us.
        components.path += symbol
        components.queryItems = [
            URLQueryItem(name: "range", value: range.rawValue),
            URLQueryItem(name: "interval", value: interval(for: range)),
            URLQueryItem(name: "includePrePost", value: "false"),
            URLQueryItem(name: "events", value: ""),
        ]
        return components.url!
    }

    public static func searchURL(query: String) -> URL {
        var components = URLComponents(url: searchEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "quotesCount", value: "8"),
            URLQueryItem(name: "newsCount", value: "0"),
            URLQueryItem(name: "listsCount", value: "0"),
            URLQueryItem(name: "enableFuzzyQuery", value: "false"),
        ]
        return components.url!
    }

    static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    public func series(for symbol: String, range: StockChartRange) async throws -> StockSeries {
        let response: YahooChartResponse = try await fetch(Self.chartURL(symbol: symbol, range: range))
        guard let result = response.chart.result?.first else {
            throw Self.error(for: response.chart.error, status: 200)
        }
        guard let series = result.series(symbol: symbol, range: range, fetchedAt: now()) else {
            throw StockError.badResponse
        }
        return series
    }

    public func search(_ query: String) async throws -> [StockSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let response: YahooSearchResponse = try await fetch(Self.searchURL(query: trimmed))
        return (response.quotes ?? []).compactMap(\.result)
    }

    private func fetch<Response: Decodable>(_ url: URL) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await loader(Self.request(for: url))
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw Self.stockError(for: error)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as StockError {
            throw error
        } catch {
            throw StockError.offline
        }
        return try Self.decode(Response.self, from: data, status: (response as? HTTPURLResponse)?.statusCode ?? 200)
    }

    /// Decodes a body, turning Yahoo's `{"chart": {"error": {...}}}` (sent with a 404 for an
    /// unknown symbol) and other non-200 statuses into `StockError`s.
    static func decode<Response: Decodable>(_ type: Response.Type, from data: Data, status: Int) throws -> Response {
        let decoder = JSONDecoder()
        if status != 200 {
            let failure = try? decoder.decode(YahooChartResponse.self, from: data)
            throw error(for: failure?.chart.error, status: status)
        }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw StockError.badResponse
        }
    }

    static func error(for failure: YahooError?, status: Int) -> StockError {
        if status == 404 || failure?.code == "Not Found" {
            return .unknownSymbol
        }
        if status == 429 {
            return .server(status: status, reason: "Too many requests. Try again in a few minutes.")
        }
        return .server(status: status, reason: failure?.description)
    }

    static func stockError(for error: URLError) -> StockError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
            .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed, .secureConnectionFailed:
            .offline
        default:
            .server(status: error.errorCode, reason: error.localizedDescription)
        }
    }
}

// MARK: - Wire format

/// `{"code": "Not Found", "description": "No data found, symbol may be delisted"}`.
struct YahooError: Decodable {
    var code: String?
    var description: String?
}

/// The parts of Yahoo's chart response the widget uses. Closes may contain `null` for
/// bars with no trade, so the series is optional-element.
struct YahooChartResponse: Decodable {
    var chart: Chart

    struct Chart: Decodable {
        var result: [Result]?
        var error: YahooError?
    }

    struct Result: Decodable {
        var meta: Meta
        var timestamp: [Double]?
        var indicators: Indicators?

        /// The quote and chart. Nil without a price. The quote is left out when the
        /// response doesn't say what the previous close was: `previousClose` is the prior
        /// day's close in every range, while `chartPreviousClose` is the close before the
        /// range began, which is the same thing only for a one-day chart.
        func series(symbol: String, range: StockChartRange, fetchedAt: Date) -> StockSeries? {
            guard let price = meta.regularMarketPrice else { return nil }

            var points: [StockChartPoint] = []
            let closes = indicators?.quote?.first?.close ?? []
            for (index, time) in (timestamp ?? []).enumerated() {
                guard closes.indices.contains(index), let close = closes[index] else { continue }
                points.append(StockChartPoint(time: Date(timeIntervalSince1970: time), close: close))
            }
            points.sort { $0.time < $1.time }

            let chart = StockChart(
                symbol: symbol, range: range, points: points, previousClose: meta.chartPreviousClose,
                fetchedAt: fetchedAt)

            let previousClose = meta.previousClose ?? (range == .oneDay ? meta.chartPreviousClose : nil)
            let quote = previousClose.map { previousClose in
                StockQuote(
                    symbol: meta.symbol ?? symbol,
                    name: [meta.shortName, meta.longName].compactMap { $0 }.first { !$0.isEmpty } ?? symbol,
                    currency: meta.currency ?? "",
                    exchange: meta.fullExchangeName ?? meta.exchangeName,
                    price: price,
                    previousClose: previousClose,
                    fractionDigits: meta.priceHint ?? 2,
                    marketTime: meta.regularMarketTime.map(Date.init(timeIntervalSince1970:)) ?? fetchedAt,
                    regularSession: meta.currentTradingPeriod?.regular?.interval,
                    timeZoneIdentifier: meta.exchangeTimezoneName,
                    fetchedAt: fetchedAt)
            }
            return StockSeries(quote: quote, chart: chart)
        }
    }

    struct Meta: Decodable {
        var symbol: String?
        var currency: String?
        var exchangeName: String?
        var fullExchangeName: String?
        var shortName: String?
        var longName: String?
        var regularMarketPrice: Double?
        var regularMarketTime: Double?
        var chartPreviousClose: Double?
        var previousClose: Double?
        var priceHint: Int?
        var exchangeTimezoneName: String?
        var currentTradingPeriod: TradingPeriods?
    }

    struct TradingPeriods: Decodable {
        var regular: Period?
    }

    struct Period: Decodable {
        var start: Double
        var end: Double

        var interval: DateInterval? {
            guard end >= start else { return nil }
            return DateInterval(start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end))
        }
    }

    struct Indicators: Decodable {
        var quote: [Quote]?
    }

    struct Quote: Decodable {
        var close: [Double?]?
    }
}

/// Yahoo's search response. Only `quotes` is used; news and lists are asked for as zero.
struct YahooSearchResponse: Decodable {
    var quotes: [Quote]?

    struct Quote: Decodable {
        var symbol: String?
        var shortname: String?
        var longname: String?
        var exchDisp: String?
        var typeDisp: String?

        /// Nil for entries without a symbol (Yahoo mixes in a few).
        var result: StockSearchResult? {
            guard let symbol, let cleaned = StockSymbols.sanitize(symbol), cleaned == symbol else { return nil }
            let name = [shortname, longname].compactMap { $0 }.first { !$0.isEmpty } ?? symbol
            return StockSearchResult(symbol: symbol, name: name, exchange: exchDisp, kind: typeDisp)
        }
    }
}
