import DockCore
import DockWidgetKit
import SwiftUI

/// The current time and date. Doubles as a world clock via `timeZone` and `label`.
/// The settings keys are declared in `ClockSettings` and listed in `docs/widgets.md`.
public enum ClockWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.clock
    public static let displayName = "Clock"
    public static let systemImage = "clock"
    public static let summary = "The current time and date."
    public static let settingsSchema = ClockSettings.schema

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

/// The clock's settings keys, and typed access to one instance's values.
struct ClockSettings {
    static let showSeconds = WidgetSettingKey(
        "showSeconds", type: .bool, default: "false",
        summary: "Show seconds in the time.")
    static let showDate = WidgetSettingKey(
        "showDate", type: .bool, default: "true",
        summary: "Show the weekday and day of the month under the time.")
    static let timeZone = WidgetSettingKey(
        "timeZone", type: .timeZone, default: "",
        summary: "Show the time in this zone instead of the Mac's, for a world clock.")
    static let label = WidgetSettingKey(
        "label", type: .text, default: "",
        summary: "A short caption, such as a city name, shown under the time instead of the date.")

    static let schema = WidgetSettingsSchema([showSeconds, showDate, timeZone, label])

    let instance: WidgetInstance

    var showSeconds: Bool { Self.showSeconds.boolValue(in: instance.settings) }
    var showDate: Bool { Self.showDate.boolValue(in: instance.settings) }
    var label: String { Self.label.value(in: instance.settings).trimmingCharacters(in: .whitespaces) }

    /// The configured zone, or the system zone when unset or unrecognized.
    var timeZone: TimeZone {
        let id = Self.timeZone.value(in: instance.settings)
        guard !id.isEmpty, let zone = TimeZone(identifier: id) else { return .current }
        return zone
    }

    /// True when a non-system zone is configured.
    var usesCustomTimeZone: Bool {
        timeZone.identifier != TimeZone.current.identifier
    }
}
