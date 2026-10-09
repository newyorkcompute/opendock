import DockCore
import DockWidgetKit
import SwiftUI

/// Today's date as a mini calendar icon plus your next event. The settings keys are
/// declared in `CalendarSettings` and listed in `docs/widgets.md`.
public enum CalendarWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.calendar
    public static let displayName = "Calendar"
    public static let systemImage = "calendar"
    public static let summary = "Today's date and your next event."
    public static let settingsSchema = CalendarSettings.schema

    public static func makeView(instance: WidgetInstance) -> AnyView {
        AnyView(CalendarTileView(instance: instance))
    }

    public static func makePopout(instance: WidgetInstance) -> AnyView? {
        AnyView(CalendarPopoutView())
    }

    public static func makeSettingsView(instance: WidgetInstance) -> AnyView? {
        AnyView(CalendarSettingsView(instance: instance))
    }
}

/// The calendar widget's settings keys.
enum CalendarSettings {
    static let showNextEvent = WidgetSettingKey(
        "showNextEvent", type: .bool, default: "true",
        summary: "Show the next event beside the date. When off, the tile is just the date icon.")

    static let schema = WidgetSettingsSchema([showNextEvent])
}
