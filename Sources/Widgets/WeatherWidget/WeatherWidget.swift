import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// Current conditions and temperature from Open-Meteo, for the Mac's location or a city.
///
/// Settings (all strings):
/// - `unit`: "celsius" or "fahrenheit"; defaults to the locale's unit
/// - `caption`: what the small line under the temperature says, "location" (default) or "condition"
/// - `locationMode`, `placeName`, `placeRegion`, `latitude`, `longitude`: see `WeatherLocationSettings`
public enum WeatherWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.weather
    public static let displayName = "Weather"
    public static let systemImage = "cloud.sun"
    public static let summary = "Current conditions and a short forecast."

    public static var defaultSettings: [String: String] {
        [
            WeatherSettings.unit: TemperatureUnit.preferred().rawValue,
            WeatherSettings.caption: WeatherSettings.Caption.location.rawValue,
            WeatherLocationSettings.mode: WeatherLocationSettings.currentMode,
        ]
    }

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

/// Typed access to a weather instance's string settings.
struct WeatherSettings {
    static let unit = "unit"
    static let caption = "caption"

    enum Caption: String {
        case location
        case condition
    }

    let instance: WidgetInstance

    var unit: TemperatureUnit { TemperatureUnit(setting: instance.settings[Self.unit]) }
    var caption: Caption { instance.settings[Self.caption].flatMap(Caption.init(rawValue:)) ?? .location }
    var location: WeatherLocation { WeatherLocationSettings.location(from: instance.settings) }
}
