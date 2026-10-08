import BatteryWidget
import CalendarWidget
import ClockWidget
import DockCore
import DockWidgetKit
import NowPlayingWidget
import SystemActivityWidget
import WeatherWidget

/// The widgets that ship with OpenDock. The app registers them, `DockStorage` validates
/// saved settings against their schemas, and `docs/widgets.md` is generated from them, so
/// a new built-in widget only needs adding here.
public enum BuiltInWidgets {
    /// In the order the widget library lists them.
    public static let all: [any DockWidget.Type] = [
        ClockWidget.self,
        BatteryWidget.self,
        CalendarWidget.self,
        SystemActivityWidget.self,
        WeatherWidget.self,
        NowPlayingWidget.self,
    ]

    /// Settings schemas by type ID, for `DockStorage`.
    public static var settingsSchemas: [String: WidgetSettingsSchema] {
        WidgetRegistry.settingsSchemas(of: all)
    }
}
