import DockCore
import DockWidgetKit
import SwiftUI

/// Today's date as a mini calendar icon plus your next event.
///
/// Settings: `showNextEvent` ("true"/"false", default "true"). When "false" the
/// tile is just the date icon.
public enum CalendarWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.calendar
    public static let displayName = "Calendar"
    public static let systemImage = "calendar"
    public static let summary = "Today's date and your next event."

    public static var defaultSettings: [String: String] {
        [CalendarSettings.showNextEvent: "true"]
    }

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

/// Setting keys used by the calendar widget.
enum CalendarSettings {
    static let showNextEvent = "showNextEvent"

    static func showNextEvent(in instance: WidgetInstance) -> Bool {
        instance.settings[showNextEvent] != "false"
    }
}

extension Color {
    /// Parses `#RRGGBB`; falls back to the system blue on malformed input.
    init(hex: String) {
        var string = hex
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = UInt32(string, radix: 16) else {
            self = .blue
            return
        }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
