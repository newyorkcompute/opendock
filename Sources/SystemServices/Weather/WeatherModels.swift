import Foundation

/// A place weather can be fetched for: coordinates plus how to label them.
public struct WeatherPlace: Hashable, Codable, Sendable, Identifiable {
    public var id: String { "\(latitude),\(longitude)" }
    /// The city or town, e.g. "Oslo".
    public var name: String
    /// Where that is, for telling same-named places apart, e.g. "Norway" or "Minnesota, United States".
    public var region: String?
    public var latitude: Double
    public var longitude: Double

    public init(name: String, region: String? = nil, latitude: Double, longitude: Double) {
        self.name = name
        self.region = region
        self.latitude = latitude
        self.longitude = longitude
    }

    /// "Oslo, Norway", or just the name when there's no region.
    public var fullName: String {
        guard let region, !region.isEmpty else { return name }
        return "\(name), \(region)"
    }
}

/// Where a weather tile gets its weather from.
public enum WeatherLocation: Hashable, Sendable {
    /// The Mac's location, from Location Services.
    case current
    /// A city the user picked.
    case place(WeatherPlace)

    /// Key for caches and the per-location feeds.
    public var key: String {
        switch self {
        case .current: "current"
        case .place(let place): "place-\(place.latitude)-\(place.longitude)"
        }
    }

    public var place: WeatherPlace? {
        if case .place(let place) = self { return place }
        return nil
    }
}

/// Setting keys a weather tile stores its location under, and the parsing both ways.
/// Lives here rather than in the widget so it can be unit tested.
public enum WeatherLocationSettings {
    public static let mode = "locationMode"
    public static let placeName = "placeName"
    public static let placeRegion = "placeRegion"
    public static let latitude = "latitude"
    public static let longitude = "longitude"

    public static let currentMode = "current"
    public static let placeMode = "place"

    /// Reads a location from widget settings. Anything but a complete manual place means the current location.
    public static func location(from settings: [String: String]) -> WeatherLocation {
        guard settings[mode] == placeMode,
            let latitudeText = settings[latitude], let latitude = Double(latitudeText),
            let longitudeText = settings[longitude], let longitude = Double(longitudeText),
            (-90 ... 90).contains(latitude), (-180 ... 180).contains(longitude)
        else { return .current }
        let name = settings[placeName]?.trimmingCharacters(in: .whitespaces) ?? ""
        let region = settings[placeRegion]?.trimmingCharacters(in: .whitespaces)
        return .place(
            WeatherPlace(
                name: name.isEmpty ? "\(latitude), \(longitude)" : name,
                region: region?.isEmpty == false ? region : nil,
                latitude: latitude,
                longitude: longitude
            ))
    }

    /// Writes `location` into `settings`, replacing any previous place.
    public static func write(_ location: WeatherLocation, into settings: inout [String: String]) {
        switch location {
        case .current:
            settings[mode] = currentMode
            settings[placeName] = nil
            settings[placeRegion] = nil
            settings[latitude] = nil
            settings[longitude] = nil
        case .place(let place):
            settings[mode] = placeMode
            settings[placeName] = place.name
            settings[placeRegion] = place.region
            settings[latitude] = String(place.latitude)
            settings[longitude] = String(place.longitude)
        }
    }
}

/// The temperature scale to show. Weather is always fetched in Celsius and converted here.
public enum TemperatureUnit: String, CaseIterable, Sendable, Codable {
    case celsius
    case fahrenheit

    /// Fahrenheit for locales that use it (the US and a few others), Celsius everywhere else.
    public static func preferred(for locale: Locale = .current) -> TemperatureUnit {
        locale.measurementSystem == .us ? .fahrenheit : .celsius
    }

    /// Parses a stored setting; unknown or missing values fall back to the locale's unit.
    public init(setting: String?, locale: Locale = .current) {
        self = setting.flatMap(TemperatureUnit.init(rawValue:)) ?? .preferred(for: locale)
    }

    public var symbol: String {
        switch self {
        case .celsius: "°C"
        case .fahrenheit: "°F"
        }
    }

    /// Converts a Celsius reading to this unit.
    public func value(fromCelsius celsius: Double) -> Double {
        switch self {
        case .celsius: celsius
        case .fahrenheit: celsius * 9 / 5 + 32
        }
    }

    /// A rounded whole-degree string such as "16°" (never "-0°").
    public func format(celsius: Double) -> String {
        var rounded = value(fromCelsius: celsius).rounded()
        if rounded == 0 { rounded = 0 }
        return "\(Int(rounded))°"
    }
}

/// Weather conditions, grouped from the WMO weather interpretation codes Open-Meteo returns.
public enum WeatherCondition: String, Sendable, Codable, CaseIterable {
    case clear
    case mostlyClear
    case partlyCloudy
    case overcast
    case fog
    case drizzle
    case freezingDrizzle
    case rain
    case heavyRain
    case freezingRain
    case snow
    case heavySnow
    case snowGrains
    case rainShowers
    case heavyRainShowers
    case snowShowers
    case thunderstorm
    case thunderstormWithHail
    case unknown

    /// Maps a WMO code (0–99) to a condition. Codes Open-Meteo doesn't document map to `unknown`.
    public init(wmoCode: Int) {
        switch wmoCode {
        case 0: self = .clear
        case 1: self = .mostlyClear
        case 2: self = .partlyCloudy
        case 3: self = .overcast
        case 45, 48: self = .fog
        case 51, 53, 55: self = .drizzle
        case 56, 57: self = .freezingDrizzle
        case 61, 63: self = .rain
        case 65: self = .heavyRain
        case 66, 67: self = .freezingRain
        case 71, 73: self = .snow
        case 75: self = .heavySnow
        case 77: self = .snowGrains
        case 80, 81: self = .rainShowers
        case 82: self = .heavyRainShowers
        case 85, 86: self = .snowShowers
        case 95: self = .thunderstorm
        case 96, 99: self = .thunderstormWithHail
        default: self = .unknown
        }
    }

    /// A short, capitalized description such as "Partly cloudy".
    public var description: String {
        switch self {
        case .clear: "Clear"
        case .mostlyClear: "Mostly clear"
        case .partlyCloudy: "Partly cloudy"
        case .overcast: "Overcast"
        case .fog: "Fog"
        case .drizzle: "Drizzle"
        case .freezingDrizzle: "Freezing drizzle"
        case .rain: "Rain"
        case .heavyRain: "Heavy rain"
        case .freezingRain: "Freezing rain"
        case .snow: "Snow"
        case .heavySnow: "Heavy snow"
        case .snowGrains: "Snow grains"
        case .rainShowers: "Showers"
        case .heavyRainShowers: "Heavy showers"
        case .snowShowers: "Snow showers"
        case .thunderstorm: "Thunderstorm"
        case .thunderstormWithHail: "Thunderstorm with hail"
        case .unknown: "Unknown"
        }
    }

    /// The SF Symbol for this condition, with a night variant where one exists.
    public func symbolName(isDay: Bool) -> String {
        switch self {
        case .clear: isDay ? "sun.max.fill" : "moon.stars.fill"
        case .mostlyClear: isDay ? "sun.min.fill" : "moon.fill"
        case .partlyCloudy: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .overcast: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .freezingDrizzle, .freezingRain: "cloud.sleet.fill"
        case .rain: "cloud.rain.fill"
        case .heavyRain, .heavyRainShowers: "cloud.heavyrain.fill"
        case .snow, .snowGrains, .snowShowers: "cloud.snow.fill"
        case .heavySnow: "snowflake"
        case .rainShowers: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case .thunderstorm: "cloud.bolt.fill"
        case .thunderstormWithHail: "cloud.bolt.rain.fill"
        case .unknown: "cloud.fill"
        }
    }

    /// True for conditions with rain, snow, or hail falling.
    public var hasPrecipitation: Bool {
        switch self {
        case .clear, .mostlyClear, .partlyCloudy, .overcast, .fog, .unknown: false
        default: true
        }
    }
}

/// The weather right now.
public struct CurrentWeather: Hashable, Codable, Sendable {
    public var time: Date
    public var temperatureCelsius: Double
    public var apparentTemperatureCelsius: Double?
    /// Relative humidity, 0–100.
    public var humidity: Int?
    /// Wind speed in km/h.
    public var windSpeedKilometersPerHour: Double?
    public var condition: WeatherCondition
    public var isDay: Bool

    public init(
        time: Date,
        temperatureCelsius: Double,
        apparentTemperatureCelsius: Double? = nil,
        humidity: Int? = nil,
        windSpeedKilometersPerHour: Double? = nil,
        condition: WeatherCondition,
        isDay: Bool
    ) {
        self.time = time
        self.temperatureCelsius = temperatureCelsius
        self.apparentTemperatureCelsius = apparentTemperatureCelsius
        self.humidity = humidity
        self.windSpeedKilometersPerHour = windSpeedKilometersPerHour
        self.condition = condition
        self.isDay = isDay
    }

    public var symbolName: String { condition.symbolName(isDay: isDay) }
}

/// One hour of the forecast.
public struct HourlyForecast: Hashable, Codable, Sendable, Identifiable {
    public var id: Date { time }
    public var time: Date
    public var temperatureCelsius: Double
    public var condition: WeatherCondition
    public var isDay: Bool
    /// Chance of precipitation, 0–100, when the model provides it.
    public var precipitationProbability: Int?

    public init(
        time: Date, temperatureCelsius: Double, condition: WeatherCondition, isDay: Bool,
        precipitationProbability: Int? = nil
    ) {
        self.time = time
        self.temperatureCelsius = temperatureCelsius
        self.condition = condition
        self.isDay = isDay
        self.precipitationProbability = precipitationProbability
    }

    public var symbolName: String { condition.symbolName(isDay: isDay) }
}

/// One day of the forecast.
public struct DailyForecast: Hashable, Codable, Sendable, Identifiable {
    public var id: Date { date }
    /// Midnight at the start of the day, in the place's time zone.
    public var date: Date
    public var condition: WeatherCondition
    public var highCelsius: Double
    public var lowCelsius: Double

    public init(date: Date, condition: WeatherCondition, highCelsius: Double, lowCelsius: Double) {
        self.date = date
        self.condition = condition
        self.highCelsius = highCelsius
        self.lowCelsius = lowCelsius
    }
}

/// Everything one fetch returns, in Celsius. Codable so the last report can be cached.
public struct WeatherReport: Hashable, Codable, Sendable {
    public var place: WeatherPlace
    /// IANA identifier of the place's time zone, for hour and day labels.
    public var timeZoneIdentifier: String
    /// When the data was fetched.
    public var fetchedAt: Date
    public var current: CurrentWeather
    public var hourly: [HourlyForecast]
    public var daily: [DailyForecast]

    public init(
        place: WeatherPlace,
        timeZoneIdentifier: String,
        fetchedAt: Date,
        current: CurrentWeather,
        hourly: [HourlyForecast],
        daily: [DailyForecast]
    ) {
        self.place = place
        self.timeZoneIdentifier = timeZoneIdentifier
        self.fetchedAt = fetchedAt
        self.current = current
        self.hourly = hourly
        self.daily = daily
    }

    /// The place's time zone, or the system's when the identifier isn't recognized.
    public var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }

    /// Hours that haven't ended yet, starting with the one in progress.
    public func upcomingHours(from now: Date, limit: Int = 12) -> [HourlyForecast] {
        Array(hourly.filter { $0.time.addingTimeInterval(3600) > now }.prefix(limit))
    }

    /// Today's forecast, for the high and low.
    public func today(at now: Date) -> DailyForecast? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return daily.first { calendar.isDate($0.date, inSameDayAs: now) }
    }
}
