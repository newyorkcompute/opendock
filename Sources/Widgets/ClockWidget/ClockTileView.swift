import DockCore
import DockWidgetKit
import SwiftUI

/// The in-dock clock tile: time on top, date (or label) below.
struct ClockTileView: View {
    let instance: WidgetInstance

    @Environment(\.dockIsVisible) private var isVisible
    @Environment(\.locale) private var locale

    var body: some View {
        let settings = ClockSettings(instance: instance)
        // Only tick every second when seconds are shown *and* the dock is on screen.
        let interval: TimeInterval = settings.showSeconds && isVisible ? 1 : 60
        let start = Date(
            timeIntervalSinceReferenceDate: (Date.now.timeIntervalSinceReferenceDate / interval).rounded(.down)
                * interval)

        TimelineView(.periodic(from: start, by: interval)) { context in
            WidgetTile {
                VStack(alignment: .leading, spacing: 0) {
                    WidgetPrimaryText(timeString(context.date, settings: settings))
                    if let caption = caption(context.date, settings: settings) {
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
