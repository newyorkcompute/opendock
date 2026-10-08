import Foundation
import Testing

@testable import SystemServices

/// Loads `Tests/SystemServicesTests/Fixtures/<name>.json`.
private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

/// A client whose every request returns `data` with `status`, recording the URLs it was asked for.
private func client(
    returning data: Data, status: Int = 200, now: Date = Date(timeIntervalSince1970: 1_791_466_500)
) -> (client: OpenMeteoClient, requests: Requests) {
    let requests = Requests()
    let client = OpenMeteoClient(
        loader: { url in
            requests.append(url)
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (data, response)
        },
        now: { now }
    )
    return (client, requests)
}

private final class Requests: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func append(_ url: URL) {
        lock.withLock { urls.append(url) }
    }

    var all: [URL] { lock.withLock { urls } }
}

private let oslo = WeatherPlace(name: "Oslo", region: "Norway", latitude: 59.91273, longitude: 10.74609)

// MARK: - Decoding

@Suite("Open-Meteo forecast decoding")
struct OpenMeteoForecastDecodingTests {
    @Test func decodesCurrentConditions() async throws {
        let (client, _) = client(returning: try fixture("open-meteo-forecast"))
        let report = try await client.forecast(latitude: oslo.latitude, longitude: oslo.longitude)

        #expect(report.timeZoneIdentifier == "Europe/Oslo")
        #expect(report.fetchedAt == Date(timeIntervalSince1970: 1_791_466_500))
        #expect(report.current.time == Date(timeIntervalSince1970: 1_791_466_200))
        #expect(report.current.temperatureCelsius == 7.1)
        #expect(report.current.apparentTemperatureCelsius == 2.4)
        #expect(report.current.humidity == 82)
        #expect(report.current.windSpeedKilometersPerHour == 23.0)
        #expect(report.current.condition == .drizzle)
        #expect(report.current.isDay)
        #expect(report.current.symbolName == "cloud.drizzle.fill")
    }

    @Test func keepsTheRequestedCoordinatesNotTheGridPoint() async throws {
        let (client, _) = client(returning: try fixture("open-meteo-forecast"))
        let report = try await client.forecast(latitude: oslo.latitude, longitude: oslo.longitude)

        // The fixture's grid point is 59.915257, 10.74292.
        #expect(report.place.latitude == oslo.latitude)
        #expect(report.place.longitude == oslo.longitude)
        #expect(report.place.name.isEmpty)
    }

    @Test func decodesTheHourlySeriesAndTheirNulls() async throws {
        let (client, _) = client(returning: try fixture("open-meteo-forecast"))
        let report = try await client.forecast(latitude: oslo.latitude, longitude: oslo.longitude)

        #expect(report.hourly.count == 24)
        let first = try #require(report.hourly.first)
        #expect(first.time == Date(timeIntervalSince1970: 1_791_464_400))
        #expect(first.temperatureCelsius == 7.0)
        #expect(first.precipitationProbability == 94)
        #expect(first.condition == .drizzle)
        // The fixture has `null` for the second hour's precipitation probability.
        #expect(report.hourly[1].precipitationProbability == nil)
        #expect(report.hourly[1].temperatureCelsius == 7.2)
        // Hours are consecutive.
        for (earlier, later) in zip(report.hourly, report.hourly.dropFirst()) {
            #expect(later.time.timeIntervalSince(earlier.time) == 3600)
        }
    }

    @Test func decodesTheDailySeries() async throws {
        let (client, _) = client(returning: try fixture("open-meteo-forecast"))
        let report = try await client.forecast(latitude: oslo.latitude, longitude: oslo.longitude)

        #expect(report.daily.count == 4)
        let today = try #require(report.daily.first)
        #expect(today.date == Date(timeIntervalSince1970: 1_791_410_400))
        #expect(today.condition == .rain)
        #expect(today.highCelsius == 10.1)
        #expect(today.lowCelsius == 6.6)
        #expect(report.daily.map(\.condition) == [.rain, .overcast, .drizzle, .drizzle])
    }

    @Test func findsTodayAndUpcomingHoursInThePlacesTimeZone() async throws {
        let (client, _) = client(returning: try fixture("open-meteo-forecast"))
        let report = try await client.forecast(latitude: oslo.latitude, longitude: oslo.longitude)
        let now = Date(timeIntervalSince1970: 1_791_466_500) // 09:35 in Oslo

        #expect(report.today(at: now)?.date == Date(timeIntervalSince1970: 1_791_410_400))
        let upcoming = report.upcomingHours(from: now, limit: 6)
        #expect(upcoming.count == 6)
        // The 09:00 hour is still in progress, so it leads.
        #expect(upcoming.first?.time == Date(timeIntervalSince1970: 1_791_464_400))
        // Three hours later, the 09:00 and 10:00 and 11:00 hours are over.
        let later = report.upcomingHours(from: now.addingTimeInterval(3 * 3600), limit: 6)
        #expect(later.first?.time == Date(timeIntervalSince1970: 1_791_475_200))
    }

    @Test func rejectsOpenMeteoErrors() async throws {
        let (client, _) = client(returning: try fixture("open-meteo-error"), status: 400)
        await #expect(
            throws: WeatherError.server(status: 400, reason: "Latitude must be in range of -90 to 90°. Given: 999.0.")
        ) {
            try await client.forecast(latitude: 999, longitude: 10)
        }
    }

    @Test func rejectsBodiesThatArentForecasts() async throws {
        let (client, _) = client(returning: Data("{\"hello\": 1}".utf8))
        await #expect(throws: WeatherError.badResponse) {
            try await client.forecast(latitude: 1, longitude: 2)
        }
    }

    @Test func reportsNetworkFailuresAsOffline() async {
        let client = OpenMeteoClient(loader: { _ in throw URLError(.notConnectedToInternet) })
        await #expect(throws: WeatherError.offline) {
            try await client.forecast(latitude: 1, longitude: 2)
        }
        #expect(OpenMeteoClient.weatherError(for: URLError(.timedOut)) == .offline)
        #expect(OpenMeteoClient.weatherError(for: URLError(.cannotFindHost)) == .offline)
        #expect(OpenMeteoClient.weatherError(for: URLError(.badServerResponse)) != .offline)
    }

    @Test func asksForEverythingTheWidgetShows() async throws {
        let (client, requests) = client(returning: try fixture("open-meteo-forecast"))
        _ = try await client.forecast(latitude: 59.912731, longitude: 10.746091)

        let url = try #require(requests.all.first)
        #expect(url.host() == "api.open-meteo.com")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(query["latitude"] == "59.9127")
        #expect(query["longitude"] == "10.7461")
        #expect(query["timeformat"] == "unixtime")
        #expect(query["timezone"] == "auto")
        #expect(query["current"]?.contains("weather_code") == true)
        #expect(query["current"]?.contains("temperature_2m") == true)
        #expect(query["hourly"]?.contains("precipitation_probability") == true)
        #expect(query["daily"]?.contains("temperature_2m_max") == true)
    }

    @Test func reportsRoundTripThroughTheCacheFormat() async throws {
        let (client, _) = client(returning: try fixture("open-meteo-forecast"))
        var report = try await client.forecast(latitude: oslo.latitude, longitude: oslo.longitude)
        report.place = oslo

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(WeatherReport.self, from: try encoder.encode(report))
        #expect(restored == report)
    }
}

@Suite("Open-Meteo geocoding decoding")
struct OpenMeteoGeocodingDecodingTests {
    @Test func decodesPlacesWithRegions() async throws {
        let (client, requests) = client(returning: try fixture("open-meteo-geocoding"))
        let places = try await client.searchPlaces(named: "Oslo")

        #expect(places.count == 5)
        let first = try #require(places.first)
        #expect(first.name == "Oslo")
        // admin1 is also "Oslo", so only the country is left.
        #expect(first.region == "Norway")
        #expect(first.fullName == "Oslo, Norway")
        #expect(first.latitude == 59.91273)
        #expect(first.longitude == 10.74609)
        #expect(places[1].fullName == "Oslo, Minnesota, United States")

        let url = try #require(requests.all.first)
        #expect(url.host() == "geocoding-api.open-meteo.com")
        #expect(url.query()?.contains("name=Oslo") == true)
    }

    @Test func noMatchesIsAnEmptyList() async throws {
        let (client, _) = client(returning: try fixture("open-meteo-geocoding-empty"))
        #expect(try await client.searchPlaces(named: "Xyzzyqq").isEmpty)
    }

    @Test func skipsTheRequestForVeryShortQueries() async throws {
        let (client, requests) = client(returning: try fixture("open-meteo-geocoding"))
        #expect(try await client.searchPlaces(named: " O ").isEmpty)
        #expect(requests.all.isEmpty)
    }
}

// MARK: - Conditions and units

@Suite("WMO weather codes")
struct WeatherConditionTests {
    @Test(
        "maps every documented code",
        arguments: [
            (0, WeatherCondition.clear), (1, .mostlyClear), (2, .partlyCloudy), (3, .overcast),
            (45, .fog), (48, .fog),
            (51, .drizzle), (53, .drizzle), (55, .drizzle), (56, .freezingDrizzle), (57, .freezingDrizzle),
            (61, .rain), (63, .rain), (65, .heavyRain), (66, .freezingRain), (67, .freezingRain),
            (71, .snow), (73, .snow), (75, .heavySnow), (77, .snowGrains),
            (80, .rainShowers), (81, .rainShowers), (82, .heavyRainShowers), (85, .snowShowers), (86, .snowShowers),
            (95, .thunderstorm), (96, .thunderstormWithHail), (99, .thunderstormWithHail),
        ])
    func mapsDocumentedCodes(code: Int, condition: WeatherCondition) {
        #expect(WeatherCondition(wmoCode: code) == condition)
    }

    @Test func undocumentedCodesAreUnknown() {
        #expect(WeatherCondition(wmoCode: 4) == .unknown)
        #expect(WeatherCondition(wmoCode: 50) == .unknown)
        #expect(WeatherCondition(wmoCode: -1) == .unknown)
        #expect(WeatherCondition(wmoCode: 100) == .unknown)
        #expect(WeatherCondition(wmoCode: 4).symbolName(isDay: true) == "cloud.fill")
    }

    @Test func clearSkiesHaveDayAndNightSymbols() {
        #expect(WeatherCondition.clear.symbolName(isDay: true) == "sun.max.fill")
        #expect(WeatherCondition.clear.symbolName(isDay: false) == "moon.stars.fill")
        #expect(WeatherCondition.partlyCloudy.symbolName(isDay: true) == "cloud.sun.fill")
        #expect(WeatherCondition.partlyCloudy.symbolName(isDay: false) == "cloud.moon.fill")
        #expect(WeatherCondition.rainShowers.symbolName(isDay: true) == "cloud.sun.rain.fill")
        #expect(WeatherCondition.rainShowers.symbolName(isDay: false) == "cloud.moon.rain.fill")
    }

    @Test func precipitationSymbolsDontDependOnDaylight() {
        // Showers are the exception: they keep a sun or moon behind the cloud.
        for condition in WeatherCondition.allCases where condition.hasPrecipitation && condition != .rainShowers {
            #expect(condition.symbolName(isDay: true) == condition.symbolName(isDay: false), "\(condition)")
        }
        #expect(WeatherCondition.thunderstorm.symbolName(isDay: false) == "cloud.bolt.fill")
        #expect(WeatherCondition.snow.symbolName(isDay: true) == "cloud.snow.fill")
    }

    @Test func everyConditionHasADescription() {
        for condition in WeatherCondition.allCases {
            #expect(!condition.description.isEmpty)
            #expect(condition.description.first?.isUppercase == true, "\(condition)")
        }
    }
}

@Suite("Temperature units")
struct TemperatureUnitTests {
    @Test func convertsAndRounds() {
        #expect(TemperatureUnit.celsius.format(celsius: 7.1) == "7°")
        #expect(TemperatureUnit.celsius.format(celsius: 7.5) == "8°")
        #expect(TemperatureUnit.celsius.format(celsius: -3.4) == "-3°")
        #expect(TemperatureUnit.fahrenheit.format(celsius: 0) == "32°")
        #expect(TemperatureUnit.fahrenheit.format(celsius: 100) == "212°")
        #expect(TemperatureUnit.fahrenheit.format(celsius: 7.1) == "45°")
        #expect(TemperatureUnit.fahrenheit.format(celsius: -40) == "-40°")
    }

    @Test func neverShowsNegativeZero() {
        #expect(TemperatureUnit.celsius.format(celsius: -0.2) == "0°")
        #expect(TemperatureUnit.fahrenheit.format(celsius: -17.8) == "0°")
    }

    @Test func followsTheLocaleByDefault() {
        #expect(TemperatureUnit.preferred(for: Locale(identifier: "en_US")) == .fahrenheit)
        #expect(TemperatureUnit.preferred(for: Locale(identifier: "en_GB")) == .celsius)
        #expect(TemperatureUnit.preferred(for: Locale(identifier: "nb_NO")) == .celsius)
        #expect(TemperatureUnit(setting: nil, locale: Locale(identifier: "en_US")) == .fahrenheit)
        #expect(TemperatureUnit(setting: "celsius", locale: Locale(identifier: "en_US")) == .celsius)
        #expect(TemperatureUnit(setting: "kelvin", locale: Locale(identifier: "de_DE")) == .celsius)
    }
}

// MARK: - Settings

@Suite("Weather location settings")
struct WeatherLocationSettingsTests {
    @Test func roundTripsAPlace() {
        var settings: [String: String] = ["unit": "celsius"]
        WeatherLocationSettings.write(.place(oslo), into: &settings)

        #expect(settings[WeatherLocationSettings.mode] == "place")
        #expect(settings[WeatherLocationSettings.placeName] == "Oslo")
        #expect(settings[WeatherLocationSettings.placeRegion] == "Norway")
        #expect(settings["unit"] == "celsius")
        #expect(WeatherLocationSettings.location(from: settings) == .place(oslo))
    }

    @Test func currentLocationClearsThePlace() {
        var settings: [String: String] = [:]
        WeatherLocationSettings.write(.place(oslo), into: &settings)
        WeatherLocationSettings.write(.current, into: &settings)

        #expect(settings[WeatherLocationSettings.mode] == "current")
        #expect(settings[WeatherLocationSettings.latitude] == nil)
        #expect(settings[WeatherLocationSettings.placeName] == nil)
        #expect(WeatherLocationSettings.location(from: settings) == .current)
    }

    @Test func incompleteOrInvalidPlacesFallBackToTheCurrentLocation() {
        #expect(WeatherLocationSettings.location(from: [:]) == .current)
        #expect(WeatherLocationSettings.location(from: [WeatherLocationSettings.mode: "place"]) == .current)
        #expect(
            WeatherLocationSettings.location(from: [
                WeatherLocationSettings.mode: "place",
                WeatherLocationSettings.latitude: "95",
                WeatherLocationSettings.longitude: "10",
            ]) == .current)
        #expect(
            WeatherLocationSettings.location(from: [
                WeatherLocationSettings.mode: "place",
                WeatherLocationSettings.latitude: "abc",
                WeatherLocationSettings.longitude: "10",
            ]) == .current)
    }

    @Test func aPlaceWithoutANameIsLabeledByItsCoordinates() {
        let location = WeatherLocationSettings.location(from: [
            WeatherLocationSettings.mode: "place",
            WeatherLocationSettings.latitude: "59.9",
            WeatherLocationSettings.longitude: "10.7",
        ])
        #expect(location.place?.name == "59.9, 10.7")
        #expect(location.place?.region == nil)
    }
}

// MARK: - Feed

/// Serves canned reports, or a failure, and counts requests.
private final class FakeWeatherProvider: WeatherProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _report: WeatherReport?
    private var _failure: WeatherError?
    private var _requests = 0

    init(report: WeatherReport? = nil, failure: WeatherError? = nil) {
        _report = report
        _failure = failure
    }

    var report: WeatherReport? {
        get { lock.withLock { _report } }
        set { lock.withLock { _report = newValue } }
    }

    var failure: WeatherError? {
        get { lock.withLock { _failure } }
        set { lock.withLock { _failure = newValue } }
    }

    var requests: Int { lock.withLock { _requests } }

    func forecast(latitude: Double, longitude: Double) async throws -> WeatherReport {
        lock.withLock { _requests += 1 }
        if let failure { throw failure }
        guard var report else { throw WeatherError.badResponse }
        report.place = WeatherPlace(name: "", latitude: latitude, longitude: longitude)
        return report
    }

    func searchPlaces(named query: String) async throws -> [WeatherPlace] { [] }
}

@MainActor
private final class FakeLocationSource: WeatherLocationSource {
    var authorization: WeatherLocationAuthorization
    var place: WeatherPlace?
    var prompts = 0
    var fixes = 0
    /// What a prompt turns `notDetermined` into.
    var answer: WeatherLocationAuthorization = .authorized

    init(authorization: WeatherLocationAuthorization = .authorized, place: WeatherPlace? = nil) {
        self.authorization = authorization
        self.place = place
    }

    func requestAuthorization() async -> WeatherLocationAuthorization {
        if authorization == .notDetermined {
            prompts += 1
            authorization = answer
        }
        return authorization
    }

    func currentPlace() async throws -> WeatherPlace {
        _ = await requestAuthorization()
        guard authorization == .authorized else { throw WeatherLocationError.denied }
        fixes += 1
        guard let place else { throw WeatherLocationError.unavailable }
        return place
    }
}

/// A clock the tests move by hand.
private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    init(_ now: Date = Date(timeIntervalSince1970: 1_791_466_500)) {
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
@Suite("WeatherFeed")
struct WeatherFeedTests {
    private let clock = ManualClock()
    private let home = WeatherPlace(name: "Brooklyn", latitude: 40.68, longitude: -73.94)

    private func fixtureReport() async throws -> WeatherReport {
        let (client, _) = client(returning: try fixture("open-meteo-forecast"), now: clock.now)
        return try await client.forecast(latitude: oslo.latitude, longitude: oslo.longitude)
    }

    private func service(
        provider: FakeWeatherProvider,
        location: FakeLocationSource = FakeLocationSource(),
        cache: InMemoryWeatherReportCache = InMemoryWeatherReportCache()
    ) -> WeatherService {
        WeatherService(provider: provider, locationSource: location, cache: cache, now: { [clock] in clock.now })
    }

    @Test func fetchesNamesAndCachesAManualPlace() async throws {
        let provider = FakeWeatherProvider(report: try await fixtureReport())
        let cache = InMemoryWeatherReportCache()
        let service = service(provider: provider, cache: cache)
        let feed = service.feed(for: .place(oslo))

        #expect(feed.report == nil)
        await feed.refresh()

        #expect(feed.error == nil)
        #expect(feed.report?.place == oslo)
        #expect(feed.report?.current.condition == .drizzle)
        #expect(cache.reports[WeatherLocation.place(oslo).key]?.place == oslo)
        #expect(provider.requests == 1)
    }

    @Test func usesLocationServicesForTheCurrentLocation() async throws {
        let provider = FakeWeatherProvider(report: try await fixtureReport())
        let location = FakeLocationSource(authorization: .notDetermined, place: home)
        let service = service(provider: provider, location: location)
        let feed = service.feed(for: .current)

        await feed.refresh()

        #expect(location.prompts == 1)
        #expect(feed.report?.place == home)
        #expect(service.locationAuthorization == .authorized)
        #expect(feed.error == nil)
    }

    @Test func doesntPromptBehindTheWelcomeWindow() async throws {
        let provider = FakeWeatherProvider(report: try await fixtureReport())
        let location = FakeLocationSource(authorization: .notDetermined, place: home)
        let service = service(provider: provider, location: location)
        let feed = service.feed(for: .current)

        await feed.refresh(mayPrompt: false)

        #expect(location.prompts == 0)
        #expect(provider.requests == 0)
        #expect(feed.error == .locationNotDetermined)

        await feed.refresh(mayPrompt: true)
        #expect(location.prompts == 1)
        #expect(feed.error == nil)
    }

    @Test func deniedLocationIsReportedWithoutFetching() async throws {
        let provider = FakeWeatherProvider(report: try await fixtureReport())
        let location = FakeLocationSource(authorization: .denied, place: home)
        let service = service(provider: provider, location: location)
        let feed = service.feed(for: .current)

        await feed.refresh()

        #expect(feed.error == .locationDenied)
        #expect(feed.report == nil)
        #expect(provider.requests == 0)
        #expect(feed.nextRefreshDelay(at: clock.now) == WeatherService.retryInterval)
    }

    @Test func keepsTheLastReportWhileOffline() async throws {
        let provider = FakeWeatherProvider(report: try await fixtureReport())
        let service = service(provider: provider)
        let feed = service.feed(for: .place(oslo))
        await feed.refresh()
        let firstReport = try #require(feed.report)

        provider.failure = .offline
        clock.advance(by: 16 * 60)
        await feed.refresh()

        #expect(feed.error == .offline)
        #expect(feed.report == firstReport)
        #expect(!feed.isStale(at: clock.now))
        clock.advance(by: 20 * 60)
        #expect(feed.isStale(at: clock.now))
    }

    @Test func startsFromTheCache() async throws {
        var cached = try await fixtureReport()
        cached.place = oslo
        let cache = InMemoryWeatherReportCache(reports: [WeatherLocation.place(oslo).key: cached])
        let provider = FakeWeatherProvider(failure: .offline)
        let service = service(provider: provider, cache: cache)

        let feed = service.feed(for: .place(oslo))
        #expect(feed.report == cached)

        // Fresh enough: no request at all.
        await feed.refresh()
        #expect(provider.requests == 0)
        #expect(feed.error == nil)
    }

    @Test func refreshesOnlyWhenDue() async throws {
        let provider = FakeWeatherProvider(report: try await fixtureReport())
        let service = service(provider: provider)
        let feed = service.feed(for: .place(oslo))

        await feed.refresh()
        await feed.refresh()
        #expect(provider.requests == 1)

        clock.advance(by: 14 * 60)
        #expect(!feed.isDue(at: clock.now))
        await feed.refresh()
        #expect(provider.requests == 1)

        clock.advance(by: 2 * 60)
        #expect(feed.isDue(at: clock.now))
        await feed.refresh()
        #expect(provider.requests == 2)

        await feed.refresh(force: true)
        #expect(provider.requests == 3)
    }

    @Test func retriesFailuresSooner() async throws {
        let provider = FakeWeatherProvider(failure: .server(status: 500, reason: nil))
        let service = service(provider: provider)
        let feed = service.feed(for: .place(oslo))

        await feed.refresh()
        #expect(feed.error == .server(nil))
        #expect(feed.nextRefreshDelay(at: clock.now) == WeatherService.retryInterval)

        clock.advance(by: 30)
        await feed.refresh()
        #expect(provider.requests == 1)

        clock.advance(by: 31)
        provider.failure = nil
        provider.report = try await fixtureReport()
        await feed.refresh()
        #expect(provider.requests == 2)
        #expect(feed.error == nil)
        #expect(feed.nextRefreshDelay(at: clock.now) == WeatherService.refreshInterval)
    }

    @Test func tilesForTheSamePlaceShareAFeed() async throws {
        let service = service(provider: FakeWeatherProvider())
        #expect(service.feed(for: .place(oslo)) === service.feed(for: .place(oslo)))
        #expect(service.feed(for: .place(oslo)) !== service.feed(for: .current))
        #expect(service.feed(for: .current) === service.feed(for: .current))
    }
}
