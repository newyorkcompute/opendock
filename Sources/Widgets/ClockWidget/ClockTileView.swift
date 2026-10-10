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
            .widgetAccessibility(reading(now, settings: settings), updatesFrequently: settings.showSeconds)
        }
    }

    /// The name is "Clock"; the value is the time plus the caption VoiceOver should hear.
    /// Seconds tick visually, but `updatesFrequently` keeps VoiceOver from re-speaking each one.
    private func reading(_ date: Date, settings: ClockSettings) -> WidgetAccessibilityReading {
        var parts = [timeString(date, settings: settings)]
        if !settings.label.isEmpty {
            parts.append(settings.label)
        } else if settings.showDate {
            parts.append(
                date.formatted(
                    Date.FormatStyle(locale: locale, timeZone: settings.timeZone)
                        .weekday(.wide).month(.wide).day()
                )
            )
        }
        if settings.usesCustomTimeZone, settings.label.isEmpty {
            let name =
                settings.timeZone.identifier.split(separator: "/").last.map {
                    $0.replacingOccurrences(of: "_", with: " ")
                } ?? settings.timeZone.identifier
            parts.append(name)
        }
        return WidgetAccessibility.reading("Clock", value: parts)
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
