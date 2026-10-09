import DockCore
import DockWidgetKit
import SwiftUI

/// The in-dock clock tile: time on top, date (or label) below.
struct ClockTileView: View {
    let instance: WidgetInstance

    @Environment(\.dockEdge) private var edge
    @Environment(\.locale) private var locale

    var body: some View {
        let settings = ClockSettings(instance: instance)
        WidgetTicking(interval: settings.showSeconds ? 1 : 60) { now in
            WidgetTile {
                // Centered in the narrow tile of a side edge.
                VStack(alignment: edge.isVertical ? .center : .leading, spacing: 0) {
                    WidgetPrimaryText(timeString(now, settings: settings))
                    if let caption = caption(now, settings: settings) {
                        WidgetSecondaryText(caption)
                    }
                }
            }
        }
    }

    private func timeString(_ date: Date, settings: ClockSettings) -> String {
        var style = Date.FormatStyle(locale: locale, timeZone: settings.timeZone)
            .hour(.defaultDigits(amPM: .abbreviated))
            .minute()
        if settings.showSeconds { style = style.second() }
        return date.formatted(style)
    }

    private func caption(_ date: Date, settings: ClockSettings) -> String? {
        if !settings.label.isEmpty { return settings.label }
        guard settings.showDate else { return nil }
        return date.formatted(
            Date.FormatStyle(locale: locale, timeZone: settings.timeZone).weekday(.abbreviated).day()
        )
    }
}
