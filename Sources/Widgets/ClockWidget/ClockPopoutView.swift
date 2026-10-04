import DockCore
import SwiftUI

/// A month calendar for the clock's time zone with today highlighted.
struct ClockPopoutView: View {
    let instance: WidgetInstance

    @Environment(\.locale) private var locale

    var body: some View {
        let settings = ClockSettings(instance: instance)
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 10) {
                header(now: context.date, settings: settings)
                MonthGrid(now: context.date, timeZone: settings.timeZone)
            }
        }
        .padding(16)
        .frame(width: 252, alignment: .leading)
    }

    private func header(now: Date, settings: ClockSettings) -> some View {
        let style = Date.FormatStyle(locale: locale, timeZone: settings.timeZone)
        return VStack(alignment: .leading, spacing: 2) {
            Text(now.formatted(style.weekday(.wide).month(.wide).day().year()))
                .font(.headline)
            if settings.usesCustomTimeZone {
                Text(zoneDescription(settings.timeZone, at: now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "Oslo · GMT+2 (+6 hr)"
    private func zoneDescription(_ zone: TimeZone, at date: Date) -> String {
        let name = zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone.identifier
        let offsetSeconds = zone.secondsFromGMT(for: date)
        let hours = Double(offsetSeconds) / 3600
        let gmt = "GMT" + (hours == hours.rounded() ? String(format: "%+.0f", hours) : String(format: "%+.1f", hours))
        let delta = Double(offsetSeconds - TimeZone.current.secondsFromGMT(for: date)) / 3600
        let relative = delta == 0 ? "" : " (" + (delta == delta.rounded() ? String(format: "%+.0f", delta) : String(format: "%+.1f", delta)) + " hr)"
        return "\(name) · \(gmt)\(relative)"
    }
}

/// A compact month grid. Weekday order follows the user's locale.
private struct MonthGrid: View {
    let now: Date
    let timeZone: TimeZone

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    /// Day numbers for the month, with `nil` padding before the first day.
    private var cells: [Int?] {
        let calendar = calendar
        guard let monthStart = calendar.dateInterval(of: .month, for: now)?.start,
              let days = calendar.range(of: .day, in: .month, for: now)
        else { return [] }
        let weekday = calendar.component(.weekday, from: monthStart)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + days.map { Optional($0) }
    }

    var body: some View {
        let today = calendar.component(.day, from: now)
        VStack(spacing: 4) {
            Text(now.formatted(Date.FormatStyle(timeZone: timeZone).month(.wide).year()))
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        Text("\(day)")
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(day == today ? Color.white : Color.primary)
                            .frame(width: 28, height: 24)
                            .background {
                                if day == today { Circle().fill(Color.accentColor) }
                            }
                    } else {
                        Color.clear.frame(height: 24)
                    }
                }
            }
        }
    }
}
