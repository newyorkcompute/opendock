import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// Current conditions and temperature from Open-Meteo, for the Mac's location or a city.
/// The settings keys are declared in `WeatherSettings` and listed in `docs/widgets.md`; the
/// location keys are read and written by `WeatherLocationSettings` in `SystemServices`.
public enum WeatherWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.weather
    public static let displayName = "Weather"
    public static let systemImage = "cloud.sun"
    public static let summary = "Current conditions and a short forecast."
    public static let settingsSchema = WeatherSettings.schema

    public static func makeView(instance: WidgetInstance) -> AnyView {
        AnyView(WeatherTileView(instance: instance))
    }

    public static func makePopout(instance: WidgetInstance) -> AnyView? {
        AnyView(WeatherPopoutView(instance: instance))
    }

    public static func makeSettingsView(instance: WidgetInstance) -> AnyView? {
        AnyView(WeatherSettingsView(instance: instance))
    }
}

/// The weather widget's settings keys, and typed access to one instance's values.
struct WeatherSettings {
    enum Caption: String, CaseIterable {
        case location
        case condition
    }

    /// `""` means the Mac's region setting, so a tile follows it until the user picks a scale.
    static let unit = WidgetSettingKey(
        "unit", type: .choice(TemperatureUnit.allCases.map(\.rawValue)), default: "",
        summary: "Temperature scale. Empty means the Mac's region setting: Fahrenheit in the US, Celsius elsewhere.")
    static let caption = WidgetSettingKey(
        "caption", type: .choice(Caption.allCases.map(\.rawValue)), default: Caption.location.rawValue,
        summary: "What the small line under the temperature says: the place's name, or the conditions.")
    static let locationMode = WidgetSettingKey(
        WeatherLocationSettings.mode,
        type: .choice([WeatherLocationSettings.currentMode, WeatherLocationSettings.placeMode]),
        default: WeatherLocationSettings.currentMode,
        summary: "Where the weather is for: the Mac's location, or the place in the keys below.")
    static let placeName = WidgetSettingKey(
        WeatherLocationSettings.placeName, type: .text, default: "",
        summary: "Name of the chosen place, such as a city. Only used when `locationMode` is `\"place\"`.")
    static let placeRegion = WidgetSettingKey(
        WeatherLocationSettings.placeRegion, type: .text, default: "",
        summary: "Region or country of the chosen place, shown in the popover.")
    static let latitude = WidgetSettingKey(
        WeatherLocationSettings.latitude, type: .number(-90 ... 90), default: "",
        summary: "Latitude of the chosen place, in degrees. Without both coordinates the tile uses the Mac's location.")
    static let longitude = WidgetSettingKey(
        WeatherLocationSettings.longitude, type: .number(-180 ... 180), default: "",
        summary: "Longitude of the chosen place, in degrees.")

    static let schema = WidgetSettingsSchema([
        unit, caption, locationMode, placeName, placeRegion, latitude, longitude,
    ])

    let instance: WidgetInstance

    var unit: TemperatureUnit { TemperatureUnit(setting: Self.unit.value(in: instance.settings)) }
    var caption: Caption { Caption(rawValue: Self.caption.value(in: instance.settings)) ?? .location }
    var location: WeatherLocation { WeatherLocationSettings.location(from: instance.settings) }
}
