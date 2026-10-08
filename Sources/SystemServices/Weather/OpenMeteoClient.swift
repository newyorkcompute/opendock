import Foundation

/// Where weather and place lookups come from. `OpenMeteoClient` talks to Open-Meteo;
/// tests use a fake.
public protocol WeatherProvider: Sendable {
    /// The current conditions and a short forecast for the coordinates.
    func forecast(latitude: Double, longitude: Double) async throws -> WeatherReport
    /// Places matching a city name, best match first.
    func searchPlaces(named query: String) async throws -> [WeatherPlace]
}

/// Why a weather request failed, in terms the widget can explain.
public enum WeatherError: Error, Equatable, Sendable {
    /// No network, a timeout, or the host couldn't be reached.
    case offline
    /// The server answered with an error (`reason` is its message when it sent one).
    case server(status: Int, reason: String?)
    /// The server's answer couldn't be read.
    case badResponse
}

/// Fetches `url`. The default uses `URLSession`; tests return fixtures.
public typealias HTTPDataLoader = @Sendable (URL) async throws -> (Data, URLResponse)

/// Open-Meteo's forecast and geocoding APIs (https://open-meteo.com). Free for
/// non-commercial use without a key; the data is CC BY 4.0, so OpenDock shows
/// "Weather data by Open-Meteo" wherever it shows the weather.
public struct OpenMeteoClient: WeatherProvider {
    public static let forecastEndpoint = URL(string: "https://api.open-meteo.com/v1/forecast")!
    public static let geocodingEndpoint = URL(string: "https://geocoding-api.open-meteo.com/v1/search")!
    /// What to show as the data source, per Open-Meteo's attribution requirement.
    public static let attribution = "Weather data by Open-Meteo"
    public static let attributionURL = URL(string: "https://open-meteo.com/")!

    private let loader: HTTPDataLoader
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - loader: fetches URLs; defaults to a session with a 15-second timeout that fails
    ///     fast when offline instead of waiting for connectivity.
    ///   - now: the clock used for `fetchedAt`.
    public init(loader: HTTPDataLoader? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.loader = loader ?? { url in try await Self.session.data(from: url) }
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

    /// The forecast request for the coordinates: current conditions, the next 24 hours, and
    /// 4 days, as Unix timestamps in the place's own time zone.
    public static func forecastURL(latitude: Double, longitude: Double) -> URL {
        var components = URLComponents(url: forecastEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: coordinate(latitude)),
            URLQueryItem(name: "longitude", value: coordinate(longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,apparent_temperature,relative_humidity_2m,is_day,weather_code,wind_speed_10m"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "forecast_days", value: "4"),
            URLQueryItem(name: "forecast_hours", value: "24"),
        ]
        return components.url!
    }

    public static func geocodingURL(query: String) -> URL {
        var components = URLComponents(url: geocodingEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "8"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components.url!
    }

    /// Four decimals (about 10 m), so the cache key and URL are stable for the same place.
    private static func coordinate(_ value: Double) -> String {
        String(format: "%.4f", locale: nil, value)
    }

    public func forecast(latitude: Double, longitude: Double) async throws -> WeatherReport {
        let url = Self.forecastURL(latitude: latitude, longitude: longitude)
        let response: OpenMeteoForecastResponse = try await fetch(url)
        guard let report = response.report(requestedLatitude: latitude, requestedLongitude: longitude, fetchedAt: now())
        else { throw WeatherError.badResponse }
        return report
    }

    public func searchPlaces(named query: String) async throws -> [WeatherPlace] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let response: OpenMeteoGeocodingResponse = try await fetch(Self.geocodingURL(query: trimmed))
        return (response.results ?? []).map(\.place)
    }

    private func fetch<Response: Decodable>(_ url: URL) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await loader(url)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw Self.weatherError(for: error)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as WeatherError {
            throw error
        } catch {
            throw WeatherError.offline
        }
        return try Self.decode(Response.self, from: data, status: (response as? HTTPURLResponse)?.statusCode ?? 200)
    }

    /// Decodes a response body, turning Open-Meteo's `{"error": true, "reason": ...}` into `WeatherError.server`.
    static func decode<Response: Decodable>(_ type: Response.Type, from data: Data, status: Int) throws -> Response {
        let decoder = JSONDecoder()
        let failure = try? decoder.decode(OpenMeteoErrorResponse.self, from: data)
        if status != 200 || failure?.error == true {
            throw WeatherError.server(status: status, reason: failure?.reason)
        }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw WeatherError.badResponse
        }
    }

    static func weatherError(for error: URLError) -> WeatherError {
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

/// `{"error": true, "reason": "..."}`, which Open-Meteo sends with a 400 for bad parameters.
struct OpenMeteoErrorResponse: Decodable {
    var error: Bool?
    var reason: String?
}

/// The parts of Open-Meteo's forecast response the widget uses. Arrays may contain
/// `null` where the model has no value, so every series is optional-element.
struct OpenMeteoForecastResponse: Decodable {
    var latitude: Double
    var longitude: Double
    var timezone: String
    var current: Current
    var hourly: Hourly?
    var daily: Daily?

    struct Current: Decodable {
        var time: Double
        var temperature2m: Double
        var apparentTemperature: Double?
        var relativeHumidity2m: Double?
        var isDay: Int?
        var weatherCode: Int?
        var windSpeed10m: Double?

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case relativeHumidity2m = "relative_humidity_2m"
            case isDay = "is_day"
            case weatherCode = "weather_code"
            case windSpeed10m = "wind_speed_10m"
        }
    }

    struct Hourly: Decodable {
        var time: [Double]
        var temperature2m: [Double?]
        var weatherCode: [Int?]?
        var precipitationProbability: [Int?]?
        var isDay: [Int?]?

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
            case precipitationProbability = "precipitation_probability"
            case isDay = "is_day"
        }
    }

    struct Daily: Decodable {
        var time: [Double]
        var weatherCode: [Int?]?
        var temperature2mMax: [Double?]
        var temperature2mMin: [Double?]

        enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
        }
    }

    /// Builds the report. The place keeps the coordinates that were asked for, not the grid
    /// point Open-Meteo snapped to, so it matches the cache key; the name is filled in later.
    func report(requestedLatitude: Double, requestedLongitude: Double, fetchedAt: Date) -> WeatherReport? {
        let current = CurrentWeather(
            time: Date(timeIntervalSince1970: current.time),
            temperatureCelsius: current.temperature2m,
            apparentTemperatureCelsius: current.apparentTemperature,
            humidity: current.relativeHumidity2m.map { Int($0.rounded()) },
            windSpeedKilometersPerHour: current.windSpeed10m,
            condition: WeatherCondition(wmoCode: current.weatherCode ?? -1),
            isDay: (current.isDay ?? 1) != 0
        )

        var hours: [HourlyForecast] = []
        if let hourly {
            for (index, time) in hourly.time.enumerated() {
                guard let temperature = Self.value(hourly.temperature2m, at: index) else { continue }
                hours.append(
                    HourlyForecast(
                        time: Date(timeIntervalSince1970: time),
                        temperatureCelsius: temperature,
                        condition: WeatherCondition(wmoCode: Self.value(hourly.weatherCode, at: index) ?? -1),
                        isDay: (Self.value(hourly.isDay, at: index) ?? 1) != 0,
                        precipitationProbability: Self.value(hourly.precipitationProbability, at: index)
                    ))
            }
        }

        var days: [DailyForecast] = []
        if let daily {
            for (index, time) in daily.time.enumerated() {
                guard let high = Self.value(daily.temperature2mMax, at: index),
                    let low = Self.value(daily.temperature2mMin, at: index)
                else { continue }
                days.append(
                    DailyForecast(
                        date: Date(timeIntervalSince1970: time),
                        condition: WeatherCondition(wmoCode: Self.value(daily.weatherCode, at: index) ?? -1),
                        highCelsius: high,
                        lowCelsius: low
                    ))
            }
        }

        return WeatherReport(
            place: WeatherPlace(name: "", latitude: requestedLatitude, longitude: requestedLongitude),
            timeZoneIdentifier: timezone,
            fetchedAt: fetchedAt,
            current: current,
            hourly: hours,
            daily: days
        )
    }

    /// The series' value at `index`, or nil when the series is missing, short, or null there.
    private static func value<Value>(_ series: [Value?]?, at index: Int) -> Value? {
        guard let series, series.indices.contains(index) else { return nil }
        return series[index]
    }
}

/// Open-Meteo's geocoding response. `results` is absent when nothing matched.
struct OpenMeteoGeocodingResponse: Decodable {
    var results: [Result]?

    struct Result: Decodable {
        var name: String
        var latitude: Double
        var longitude: Double
        var country: String?
        var admin1: String?

        enum CodingKeys: String, CodingKey {
            case name, latitude, longitude, country, admin1
        }

        /// "Oslo, Norway" style: the state or province first when it differs from the name.
        var place: WeatherPlace {
            var parts: [String] = []
            if let admin1, !admin1.isEmpty, admin1 != name { parts.append(admin1) }
            if let country, !country.isEmpty { parts.append(country) }
            return WeatherPlace(
                name: name,
                region: parts.isEmpty ? nil : parts.joined(separator: ", "),
                latitude: latitude,
                longitude: longitude
            )
        }
    }
}
