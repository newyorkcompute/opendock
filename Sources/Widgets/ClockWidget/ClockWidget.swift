import DockCore
import DockWidgetKit
import SwiftUI

/// The current time and date. Doubles as a world clock via `timeZone` and `label`.
///
/// Settings (all strings):
/// - `showSeconds`: "true"/"false", default "false"
/// - `showDate`: "true"/"false", default "true"
/// - `timeZone`: IANA identifier such as "Europe/Oslo"; empty means the system zone
/// - `label`: short caption shown instead of the date, such as "Oslo"
public enum ClockWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.clock
    public static let displayName = "Clock"
    public static let systemImage = "clock"
    public static let summary = "The current time and date."

    public static var defaultSettings: [String: String] {
        [
            ClockSettings.showSeconds: "false",
            ClockSettings.showDate: "true",
            ClockSettings.timeZone: "",
            ClockSettings.label: "",
        ]
    }

    public static func makeView(instance: WidgetInstance) -> AnyView {
        AnyView(ClockTileView(instance: instance))
    }

    public static func makePopout(instance: WidgetInstance) -> AnyView? {
        AnyView(ClockPopoutView(instance: instance))
    }

    public static func makeSettingsView(instance: WidgetInstance) -> AnyView? {
        AnyView(ClockSettingsView(instance: instance))
    }
}

/// Typed access to a clock instance's string settings.
struct ClockSettings {
    static let showSeconds = "showSeconds"
    static let showDate = "showDate"
    static let timeZone = "timeZone"
    static let label = "label"

    let instance: WidgetInstance

    var showSeconds: Bool { instance.settings[Self.showSeconds] == "true" }
    var showDate: Bool { instance.settings[Self.showDate] != "false" }
    var label: String { (instance.settings[Self.label] ?? "").trimmingCharacters(in: .whitespaces) }

    /// The configured zone, or the system zone when unset or unrecognized.
    var timeZone: TimeZone {
        guard let id = instance.settings[Self.timeZone], !id.isEmpty, let zone = TimeZone(identifier: id) else {
            return .current
        }
        return zone
    }

    /// True when a non-system zone is configured.
    var usesCustomTimeZone: Bool {
        guard let id = instance.settings[Self.timeZone], !id.isEmpty, let zone = TimeZone(identifier: id) else {
            return false
        }
        return zone.identifier != TimeZone.current.identifier
    }
}
