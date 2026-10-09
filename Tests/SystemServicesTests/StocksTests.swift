import Foundation
import Testing

@testable import SystemServices

/// Loads `Tests/SystemServicesTests/Fixtures/<name>.json`.
private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

/// A client whose every request returns `data` with `status`, recording the requests it was asked to make.
private func client(
    returning data: Data, status: Int = 200, now: Date = Date(timeIntervalSince1970: 1_728_590_700)
) -> (client: YahooFinanceClient, requests: Requests) {
    let requests = Requests()
    let client = YahooFinanceClient(
        loader: { request in
            requests.append(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (data, response)
        },
        now: { now }
    )
    return (client, requests)
}

private final class Requests: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func append(_ request: URLRequest) {
        lock.withLock { requests.append(request) }
    }

    var all: [URLRequest] { lock.withLock { requests } }
}

private let enUS = Locale(identifier: "en_US")

// MARK: - Symbols

@Suite("Stock symbols")
struct StockSymbolsTests {
    @Test func parsesAListUpperCasedWithoutDuplicates() {
        let symbols = StockSymbols.parse("aapl, msft,AAPL ,^gspc; brk-b\nEURUSD=X")
        #expect(symbols == ["AAPL", "MSFT", "^GSPC", "BRK-B", "EURUSD=X"])
    }

    @Test func dropsCharactersATickerCantContainAndBlanks() {
        #expect(StockSymbols.parse(" a$pl , , ***, 12, 🍎 ") == ["APL", "12"])
        #expect(StockSymbols.sanitize("***") == nil)
        #expect(StockSymbols.sanitize("  ") == nil)
        #expect(StockSymbols.sanitize("$aapl") == "AAPL")
        #expect(StockSymbols.sanitize("brk.b") == "BRK.B")
    }

    @Test func rejectsSymbolsThatAreTooLong() {
        #expect(StockSymbols.sanitize("AAPL260116C00150000") == nil)
        #expect(StockSymbols.sanitize(String(repeating: "A", count: StockSymbols.maximumLength)) != nil)
    }

    @Test func keepsTheFirstTwentySymbols() {
        let many = (1 ... 30).map { "S\($0)" }.joined(separator: ",")
        let symbols = StockSymbols.parse(many)
        #expect(symbols.count == StockSymbols.maximumCount)
        #expect(symbols.first == "S1")
        #expect(symbols.last == "S20")
    }

    @Test func storageValueRoundTrips() {
        let symbols = ["AAPL", "^GSPC", "BTC-USD"]
        let stored = StockSymbols.storageValue(symbols)
        #expect(stored == "AAPL, ^GSPC, BTC-USD")
        #expect(StockSymbols.parse(stored) == symbols)
        #expect(StockSymbols.storageValue([]) == "")
        #expect(StockSymbols.parse("") == [])
    }
}

// MARK: - Formatting

@Suite("Stock formatting")
struct StockFormattingTests {
    @Test func pricesUseTheCurrencySymbol() {
        #expect(StockFormatting.price(229.04, currency: "USD", locale: enUS) == "$229.04")
        #expect(StockFormatting.price(12.5, currency: "EUR", locale: enUS) == "€12.50")
        #expect(StockFormatting.price(38000, currency: "JPY", fractionDigits: 0, locale: enUS) == "¥38,000")
    }

    @Test func codesThatArentISOFollowTheNumber() {
        #expect(StockFormatting.price(1234.5, currency: "GBp", locale: enUS) == "1,234.50 GBp")
        #expect(StockFormatting.price(1234.5, currency: "", locale: enUS) == "1,234.50")
    }

    @Test func fractionDigitsAreClampedToFour() {
        #expect(StockFormatting.price(1.0865432, currency: "USD", fractionDigits: 6, locale: enUS) == "$1.0865")
        #expect(StockFormatting.price(1.6, currency: "USD", fractionDigits: -1, locale: enUS) == "$2")
    }

    @Test func changesAreSignedExceptZero() {
        #expect(StockFormatting.change(1.234, locale: enUS) == "+1.23")
        #expect(StockFormatting.change(-0.45, locale: enUS) == "-0.45")
        #expect(StockFormatting.change(0, locale: enUS) == "0.00")
        #expect(StockFormatting.change(0.00123, fractionDigits: 4, locale: enUS) == "+0.0012")
    }

    @Test func percentsComeFromFractions() {
        #expect(StockFormatting.percent(0.0054, locale: enUS) == "+0.54%")
        #expect(StockFormatting.percent(-0.012, locale: enUS) == "-1.20%")
        #expect(StockFormatting.percent(0, locale: enUS) == "0.00%")
        #expect(StockFormatting.percent(nil, locale: enUS) == "—")
        #expect(StockFormatting.percent(.infinity, locale: enUS) == "—")
    }

    @Test func changeWithPercentCombinesBoth() {
        #expect(StockFormatting.changeWithPercent(1.23, fraction: 0.0054, locale: enUS) == "+1.23 (+0.54%)")
        #expect(StockFormatting.changeWithPercent(-2, fraction: nil, locale: enUS) == "-2.00 (—)")
    }
}

// MARK: - Models

@Suite("Stock models")
struct StockModelsTests {
    private let now = Date(timeIntervalSince1970: 1_728_590_700)

    private func quote(price: Double, previousClose: Double, session: DateInterval? = nil) -> StockQuote {
        StockQuote(
            symbol: "AAPL", name: "Apple Inc.", currency: "USD", price: price, previousClose: previousClose,
            marketTime: now, regularSession: session, fetchedAt: now)
    }

    @Test func quotesKnowTheirMove() {
        let up = quote(price: 101, previousClose: 100)
        #expect(up.change == 1)
        #expect(up.changeFraction == 0.01)
        #expect(up.move == .up)
        #expect(quote(price: 99, previousClose: 100).move == .down)
        #expect(quote(price: 100, previousClose: 100).move == .flat)
        #expect(quote(price: 5, previousClose: 0).changeFraction == nil)
        #expect(StockMove(change: nil) == .flat)
    }

    @Test func marketIsOpenDuringTheSessionOrRightAfterATrade() {
        let session = DateInterval(start: now.addingTimeInterval(-3600), duration: 2 * 3600)
        let open = quote(price: 1, previousClose: 1, session: session)
        #expect(open.isMarketOpen(at: now))
        #expect(!open.isMarketOpen(at: now.addingTimeInterval(2 * 3600)))
        let unknownSession = quote(price: 1, previousClose: 1)
        #expect(unknownSession.isMarketOpen(at: now.addingTimeInterval(10 * 60)))
        #expect(!unknownSession.isMarketOpen(at: now.addingTimeInterval(30 * 60)))
    }

    @Test func chartsMeasureChangeFromTheBaselineOrTheFirstPoint() {
        let points = [10.0, 12, 11].enumerated().map {
            StockChartPoint(time: now.addingTimeInterval(Double($0.offset) * 60), close: $0.element)
        }
        let withBaseline = StockChart(symbol: "X", range: .oneDay, points: points, previousClose: 8, fetchedAt: now)
        #expect(withBaseline.change == 3)
        #expect(withBaseline.changeFraction == 0.375)
        #expect(withBaseline.low == 10)
        #expect(withBaseline.high == 12)
        let withoutBaseline = StockChart(
            symbol: "X", range: .oneYear, points: points, previousClose: nil, fetchedAt: now)
        #expect(withoutBaseline.change == 1)
        #expect(withoutBaseline.changeFraction == 0.1)
        let empty = StockChart(symbol: "X", range: .oneDay, points: [], previousClose: 8, fetchedAt: now)
        #expect(empty.change == nil)
        #expect(empty.changeFraction == nil)
    }

    @Test func everyRangeHasATitleAndABarSize() {
        let titles = StockChartRange.allCases.map(\.title)
        #expect(titles == ["1D", "5D", "1M", "6M", "1Y"])
        #expect(Set(StockChartRange.allCases.map(YahooFinanceClient.interval(for:))).count == 4)
        #expect(StockChartRange(rawValue: "1mo") == .oneMonth)
    }
}

@Suite("Stock chart layout")
struct StockChartLayoutTests {
    @Test func scalesClosesBetweenTheLowAndHigh() {
        let layout = StockChartLayout.make(closes: [10, 20, 15], previousClose: nil)
        #expect(layout.values == [0, 1, 0.5])
        #expect(layout.baseline == nil)
    }

    @Test func keepsThePreviousCloseInView() {
        let below = StockChartLayout.make(closes: [10, 12], previousClose: 8)
        #expect(below.values == [0.5, 1])
        #expect(below.baseline == 0)
        let above = StockChartLayout.make(closes: [10, 12], previousClose: 14)
        #expect(above.values == [0, 0.5])
        #expect(above.baseline == 1)
    }

    @Test func aFlatSeriesSitsInTheMiddle() {
        let layout = StockChartLayout.make(closes: [7, 7, 7], previousClose: 7)
        #expect(layout.values == [0.5, 0.5, 0.5])
        #expect(layout.baseline == 0.5)
        #expect(StockChartLayout.make(closes: [], previousClose: 7) == StockChartLayout(values: [], baseline: nil))
    }

    @Test func pointsAreSpacedEvenlyUnlessADayIsLaidOutOverItsSession() {
        let start = Date(timeIntervalSince1970: 1_728_567_000)
        let session = DateInterval(start: start, duration: 6.5 * 3600)
        let points = [0.0, 3600, 3.25 * 3600].map { StockChartPoint(time: start.addingTimeInterval($0), close: 1) }
        let day = StockChart(symbol: "X", range: .oneDay, points: points, previousClose: nil, fetchedAt: start)

        #expect(StockChartLayout.make(chart: day, session: session).positions == [0, 1 / 6.5, 0.5])
        #expect(StockChartLayout.make(chart: day, session: nil).positions == [0, 0.5, 1])
        let month = StockChart(symbol: "X", range: .oneMonth, points: points, previousClose: nil, fetchedAt: start)
        #expect(StockChartLayout.make(chart: month, session: session).positions == [0, 0.5, 1])
        // Yesterday's session doesn't contain today's points, so the day is spaced evenly.
        let yesterday = DateInterval(start: start.addingTimeInterval(-86_400), duration: 6.5 * 3600)
        #expect(StockChartLayout.make(chart: day, session: yesterday).positions == [0, 0.5, 1])
        #expect(StockChartLayout.evenPositions(count: 1) == [0])
        #expect(StockChartLayout.evenPositions(count: 0) == [])
    }
}

// MARK: - Yahoo Finance decoding

@Suite("Yahoo Finance decoding")
struct YahooFinanceDecodingTests {
    private let fetchedAt = Date(timeIntervalSince1970: 1_728_590_700)

    @Test func decodesTheQuoteFromTheChartsMeta() async throws {
        let (client, _) = client(returning: try fixture("yahoo-chart-1d"))
        let series = try await client.series(for: "AAPL", range: .oneDay)
        let quote = try #require(series.quote)

        #expect(quote.symbol == "AAPL")
        #expect(quote.name == "Apple Inc.")
        #expect(quote.currency == "USD")
        #expect(quote.exchange == "NasdaqGS")
        #expect(quote.price == 229.04)
        #expect(quote.previousClose == 229.54)
        #expect(abs(quote.change + 0.5) < 1e-9)
        #expect(quote.move == .down)
        #expect(quote.fractionDigits == 2)
        #expect(quote.marketTime == Date(timeIntervalSince1970: 1_728_590_401))
        #expect(quote.regularSession?.start == Date(timeIntervalSince1970: 1_728_567_000))
        #expect(quote.regularSession?.end == Date(timeIntervalSince1970: 1_728_590_400))
        #expect(quote.timeZoneIdentifier == "America/New_York")
        #expect(quote.fetchedAt == fetchedAt)
        #expect(!quote.isMarketOpen(at: fetchedAt))
        #expect(quote.isMarketOpen(at: Date(timeIntervalSince1970: 1_728_570_000)))
    }

    @Test func decodesTheClosesAndSkipsNulls() async throws {
        let (client, _) = client(returning: try fixture("yahoo-chart-1d"))
        let chart = try await client.series(for: "AAPL", range: .oneDay).chart

        #expect(chart.symbol == "AAPL")
        #expect(chart.range == .oneDay)
        #expect(chart.previousClose == 229.54)
        #expect(chart.fetchedAt == fetchedAt)
        // Six timestamps, one with a null close.
        #expect(chart.closes == [229.1, 228.95, 229.3, 229.0, 229.04])
        #expect(chart.points.first?.time == Date(timeIntervalSince1970: 1_728_567_000))
        #expect(chart.points.last?.time == Date(timeIntervalSince1970: 1_728_590_400))
        for (earlier, later) in zip(chart.points, chart.points.dropFirst()) {
            #expect(earlier.time < later.time)
        }
        #expect(chart.low == 228.95)
        #expect(chart.high == 229.3)
    }

    @Test func aLongRangeKeepsItsOwnBaselineButTheDaysPreviousClose() async throws {
        let (client, _) = client(returning: try fixture("yahoo-chart-6mo"))
        let series = try await client.series(for: "AAPL", range: .sixMonths)

        #expect(series.chart.range == .sixMonths)
        #expect(series.chart.previousClose == 170.12)
        #expect(series.chart.points.count == 7)
        #expect(series.chart.change.map { abs($0 - 58.92) < 1e-9 } == true)
        #expect(series.quote?.previousClose == 229.54)
        #expect(series.quote?.price == 229.04)
    }

    @Test func aLongRangeWithoutPreviousCloseHasNoQuote() async throws {
        var json = try JSONSerialization.jsonObject(with: try fixture("yahoo-chart-6mo")) as! [String: Any]
        var chart = json["chart"] as! [String: Any]
        var results = chart["result"] as! [[String: Any]]
        var meta = results[0]["meta"] as! [String: Any]
        meta["previousClose"] = nil
        results[0]["meta"] = meta
        chart["result"] = results
        json["chart"] = chart
        let data = try JSONSerialization.data(withJSONObject: json)

        let (client, _) = client(returning: data)
        let series = try await client.series(for: "AAPL", range: .sixMonths)
        #expect(series.quote == nil)
        #expect(series.chart.points.count == 7)

        // Over one day, the chart's baseline is the previous close, so the quote is kept.
        let oneDay = try await client.series(for: "AAPL", range: .oneDay)
        #expect(oneDay.quote?.previousClose == 170.12)
    }

    @Test func unknownSymbolsAreAnError() async throws {
        let (notFound, _) = client(returning: try fixture("yahoo-chart-error"), status: 404)
        await #expect(throws: StockError.unknownSymbol) {
            try await notFound.series(for: "NOPE", range: .oneDay)
        }
        let okStatus = client(returning: try fixture("yahoo-chart-error")).client
        await #expect(throws: StockError.unknownSymbol) {
            try await okStatus.series(for: "NOPE", range: .oneDay)
        }
    }

    @Test func otherStatusesAreServerErrors() async throws {
        let (limited, _) = client(returning: Data("Too Many Requests".utf8), status: 429)
        await #expect(throws: StockError.server(status: 429, reason: "Too many requests. Try again in a few minutes."))
        {
            try await limited.series(for: "AAPL", range: .oneDay)
        }
        let (down, _) = client(returning: Data(), status: 503)
        await #expect(throws: StockError.server(status: 503, reason: nil)) {
            try await down.series(for: "AAPL", range: .oneDay)
        }
    }

    @Test func bodiesThatArentChartsAreBadResponses() async throws {
        let (notJSON, _) = client(returning: Data("{\"hello\": 1}".utf8))
        await #expect(throws: StockError.badResponse) {
            try await notJSON.series(for: "AAPL", range: .oneDay)
        }
        let (noPrice, _) = client(returning: Data("{\"chart\":{\"result\":[{\"meta\":{\"symbol\":\"AAPL\"}}]}}".utf8))
        await #expect(throws: StockError.badResponse) {
            try await noPrice.series(for: "AAPL", range: .oneDay)
        }
    }

    @Test func networkFailuresAreOffline() async {
        let client = YahooFinanceClient(loader: { _ in throw URLError(.notConnectedToInternet) })
        await #expect(throws: StockError.offline) {
            try await client.series(for: "AAPL", range: .oneDay)
        }
        #expect(YahooFinanceClient.stockError(for: URLError(.timedOut)) == .offline)
        #expect(YahooFinanceClient.stockError(for: URLError(.cannotFindHost)) == .offline)
        #expect(YahooFinanceClient.stockError(for: URLError(.badServerResponse)) != .offline)
    }

    @Test func asksForTheRangeAndEncodesTheSymbol() async throws {
        let (client, requests) = client(returning: try fixture("yahoo-chart-1d"))
        _ = try await client.series(for: "^GSPC", range: .oneMonth)

        let request = try #require(requests.all.first)
        let url = try #require(request.url)
        #expect(url.host() == "query1.finance.yahoo.com")
        #expect(url.path(percentEncoded: true) == "/v8/finance/chart/%5EGSPC")
        #expect(url.path(percentEncoded: false) == "/v8/finance/chart/^GSPC")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(query["range"] == "1mo")
        #expect(query["interval"] == "90m")
        #expect(query["includePrePost"] == "false")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("OpenDock") == true)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(YahooFinanceClient.chartURL(symbol: "EURUSD=X", range: .oneDay).path() == "/v8/finance/chart/EURUSD=X")
    }

    @Test func decodesSearchResultsAndSkipsWhatIsntASymbol() async throws {
        let (client, requests) = client(returning: try fixture("yahoo-search"))
        let results = try await client.search("  apple ")

        #expect(results.map(\.symbol) == ["AAPL", "APC.F", "AAPB"])
        let first = try #require(results.first)
        #expect(first.name == "Apple Inc.")
        #expect(first.exchange == "NASDAQ")
        #expect(first.kind == "Equity")
        #expect(first.detail == "NASDAQ · Equity")
        // No short or long name: the symbol stands in.
        #expect(results[2].name == "AAPB")

        let url = try #require(requests.all.first?.url)
        #expect(url.host() == "query2.finance.yahoo.com")
        #expect(url.query()?.contains("q=apple") == true)
        #expect(url.query()?.contains("newsCount=0") == true)
    }

    @Test func blankSearchesDontMakeARequest() async throws {
        let (client, requests) = client(returning: try fixture("yahoo-search"))
        #expect(try await client.search("   ").isEmpty)
        #expect(requests.all.isEmpty)
    }

    @Test func seriesRoundTripThroughTheCacheFormat() async throws {
        let (client, _) = client(returning: try fixture("yahoo-chart-1d"))
        let series = try await client.series(for: "AAPL", range: .oneDay)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(StockSeries.self, from: try encoder.encode(series))
        #expect(restored == series)
    }
}

// MARK: - Feed

/// Serves a canned series for any symbol, or a failure, and counts requests.
private final class FakeStockProvider: StockQuoteProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _failure: StockError?
    private var _requests: [(symbol: String, range: StockChartRange)] = []
    private var _price: Double = 229.04
    private var _withoutQuote = false
    let now: @Sendable () -> Date

    init(failure: StockError? = nil, now: @escaping @Sendable () -> Date) {
        _failure = failure
        self.now = now
    }

    var failure: StockError? {
        get { lock.withLock { _failure } }
        set { lock.withLock { _failure = newValue } }
    }

    var price: Double {
        get { lock.withLock { _price } }
        set { lock.withLock { _price = newValue } }
    }

    /// When set, responses carry a chart but no quote, like a long range without `previousClose`.
    var withoutQuote: Bool {
        get { lock.withLock { _withoutQuote } }
        set { lock.withLock { _withoutQuote = newValue } }
    }

    var requests: [(symbol: String, range: StockChartRange)] { lock.withLock { _requests } }

    func series(for symbol: String, range: StockChartRange) async throws -> StockSeries {
        lock.withLock { _requests.append((symbol, range)) }
        if let failure { throw failure }
        let now = now()
        let price = price
        let points = (0 ..< 3).map { StockChartPoint(time: now.addingTimeInterval(Double($0 - 3) * 300), close: price) }
        let chart = StockChart(symbol: symbol, range: range, points: points, previousClose: 228, fetchedAt: now)
        let quote = StockQuote(
            symbol: symbol, name: "\(symbol) Inc.", currency: "USD", price: price, previousClose: 228,
            marketTime: now, fetchedAt: now)
        return StockSeries(quote: withoutQuote ? nil : quote, chart: chart)
    }

    func search(_ query: String) async throws -> [StockSearchResult] { [] }
}

/// A clock the tests move by hand.
private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    init(_ now: Date = Date(timeIntervalSince1970: 1_728_590_700)) {
        _now = now
    }

    var now: Date {
        get { lock.withLock { _now } }
        set { lock.withLock { _now = newValue } }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { _now = _now.addingTimeInterval(interval) }
    }
}

@MainActor
@Suite("StockFeed")
struct StockFeedTests {
    private let clock = ManualClock()
    private let fiveMinutes: Duration = .seconds(300)

    private func provider(failure: StockError? = nil) -> FakeStockProvider {
        FakeStockProvider(failure: failure, now: { [clock] in clock.now })
    }

    private func service(provider: FakeStockProvider, cache: InMemoryStockCache = InMemoryStockCache()) -> StocksService
    {
        StocksService(provider: provider, cache: cache, now: { [clock] in clock.now })
    }

    @Test func fetchesAndCachesAQuote() async {
        let provider = provider()
        let cache = InMemoryStockCache()
        let service = service(provider: provider, cache: cache)
        let feed = service.feed(for: "AAPL")

        #expect(feed.quote == nil)
        #expect(feed.isDue(maxAge: fiveMinutes, at: clock.now))
        await feed.refresh(maxAge: fiveMinutes)

        #expect(feed.error == nil)
        #expect(feed.quote?.price == 229.04)
        #expect(feed.quote?.name == "AAPL Inc.")
        #expect(feed.chart(for: .oneDay)?.points.count == 3)
        #expect(feed.chart(for: .fiveDays) == nil)
        #expect(cache.entries["AAPL-1d"]?.quote?.symbol == "AAPL")
        #expect(provider.requests.count == 1)
        #expect(provider.requests.first?.range == .oneDay)
        #expect(!feed.isDue(maxAge: fiveMinutes, at: clock.now))
    }

    @Test func seedsFromTheCache() async {
        let provider = provider()
        let cache = InMemoryStockCache()
        let first = service(provider: provider, cache: cache)
        await first.feed(for: "AAPL").refresh()

        let second = service(provider: provider, cache: cache)
        let restored = second.feed(for: "AAPL")
        #expect(restored.quote?.price == 229.04)
        #expect(restored.chart(for: .oneDay) != nil)
        #expect(provider.requests.count == 1)
    }

    @Test func refreshesOnlyWhenTheQuoteIsOlderThanAsked() async {
        let provider = provider()
        let service = service(provider: provider)
        let feed = service.feed(for: "AAPL")

        await feed.refresh(maxAge: fiveMinutes)
        await feed.refresh(maxAge: fiveMinutes)
        #expect(provider.requests.count == 1)

        clock.advance(by: 299)
        #expect(feed.nextRefreshDelay(maxAge: fiveMinutes, at: clock.now) == .seconds(5))
        await feed.refresh(maxAge: fiveMinutes)
        #expect(provider.requests.count == 1)

        clock.advance(by: 1)
        provider.price = 230
        await feed.refresh(maxAge: fiveMinutes)
        #expect(provider.requests.count == 2)
        #expect(feed.quote?.price == 230)
    }

    @Test func neverFetchesMoreThanOnceAMinute() async {
        let provider = provider()
        let service = service(provider: provider)
        let feed = service.feed(for: "AAPL")

        await feed.refresh(maxAge: .seconds(10))
        clock.advance(by: 30)
        await feed.refresh(maxAge: .seconds(10))
        #expect(provider.requests.count == 1)
        #expect(feed.nextRefreshDelay(maxAge: .seconds(10), at: clock.now) == .seconds(30))

        clock.advance(by: 30)
        await feed.refresh(maxAge: .seconds(10))
        #expect(provider.requests.count == 2)
    }

    @Test func aForcedRefreshAlsoWaitsAMinute() async {
        let provider = provider()
        let service = service(provider: provider)
        let feed = service.feed(for: "AAPL")

        await feed.refresh(maxAge: fiveMinutes)
        #expect(!feed.canForceRefresh(at: clock.now))
        await feed.refresh(maxAge: fiveMinutes, force: true)
        #expect(provider.requests.count == 1)

        clock.advance(by: 60)
        #expect(feed.canForceRefresh(at: clock.now))
        await feed.refresh(maxAge: fiveMinutes, force: true)
        #expect(provider.requests.count == 2)
    }

    @Test func failuresKeepTheOldQuoteAndRetryAfterAMinute() async {
        let provider = provider()
        let service = service(provider: provider)
        let feed = service.feed(for: "AAPL")
        await feed.refresh(maxAge: fiveMinutes)

        clock.advance(by: 300)
        provider.failure = .offline
        await feed.refresh(maxAge: fiveMinutes)
        #expect(feed.error == .offline)
        #expect(feed.error?.shortDescription == "Offline")
        #expect(feed.quote?.price == 229.04)
        #expect(provider.requests.count == 2)

        // A failed attempt isn't retried until the retry interval has passed.
        clock.advance(by: 30)
        #expect(!feed.isDue(maxAge: fiveMinutes, at: clock.now))
        #expect(feed.nextRefreshDelay(maxAge: fiveMinutes, at: clock.now) == .seconds(30))
        await feed.refresh(maxAge: fiveMinutes)
        #expect(provider.requests.count == 2)

        clock.advance(by: 30)
        provider.failure = nil
        await feed.refresh(maxAge: fiveMinutes)
        #expect(feed.error == nil)
        #expect(provider.requests.count == 3)
    }

    @Test func errorsAreExplained() async {
        let provider = provider(failure: .unknownSymbol)
        let service = service(provider: provider)
        let feed = service.feed(for: "NOPE")
        await feed.refresh()
        #expect(feed.error == .unknownSymbol)
        #expect(feed.error?.shortDescription == "Not found")
        #expect(feed.quote == nil)

        provider.failure = .server(status: 500, reason: "boom")
        clock.advance(by: 60)
        await feed.refresh()
        #expect(feed.error == .server("boom"))
        #expect(feed.error?.description.contains("boom") == true)

        provider.failure = .badResponse
        clock.advance(by: 60)
        await feed.refresh()
        #expect(feed.error == .server("The response couldn't be read."))
    }

    @Test func concurrentCallersShareOneRequest() async {
        let provider = provider()
        let service = service(provider: provider)
        let feed = service.feed(for: "AAPL")

        async let first: Void = feed.refresh()
        async let second: Void = feed.refresh()
        _ = await (first, second)

        #expect(provider.requests.count == 1)
        #expect(feed.quote != nil)
        #expect(!feed.isRefreshing)
    }

    @Test func theServiceRefreshesAWatchlistAtOnce() async {
        let provider = provider()
        let service = service(provider: provider)
        let symbols = ["AAPL", "MSFT", "^GSPC"]

        await service.refresh(symbols, maxAge: fiveMinutes)

        #expect(Set(provider.requests.map(\.symbol)) == Set(symbols))
        #expect(provider.requests.count == 3)
        for symbol in symbols {
            #expect(service.feed(for: symbol).quote?.symbol == symbol)
        }
        #expect(service.nextRefreshDelay(for: symbols, maxAge: fiveMinutes, at: clock.now) == fiveMinutes)
        #expect(service.nextRefreshDelay(for: [], maxAge: fiveMinutes, at: clock.now) == fiveMinutes)

        let apple = service.feed(for: "AAPL")
        #expect(!apple.isStale(maxAge: fiveMinutes, at: clock.now))
        clock.advance(by: 601)
        #expect(apple.isStale(maxAge: fiveMinutes, at: clock.now))
    }

    @Test func otherRangesAreFetchedOnDemand() async {
        let provider = provider()
        let service = service(provider: provider)
        let feed = service.feed(for: "AAPL")

        await feed.refresh(range: .sixMonths, maxAge: StocksService.chartRefreshInterval)
        #expect(feed.chart(for: .sixMonths)?.range == .sixMonths)
        #expect(feed.chart(for: .oneDay) == nil)
        #expect(feed.quote?.price == 229.04)
        #expect(!feed.isDue(range: .sixMonths, maxAge: StocksService.chartRefreshInterval, at: clock.now))
        // Today's quote still needs its own fetch for the intraday chart.
        #expect(feed.isDue(maxAge: fiveMinutes, at: clock.now))

        // A response without a quote keeps the one we have.
        provider.withoutQuote = true
        provider.price = 999
        clock.advance(by: 60)
        await feed.refresh(range: .oneYear)
        #expect(feed.chart(for: .oneYear)?.closes == [999, 999, 999])
        #expect(feed.quote?.price == 229.04)
    }
}
