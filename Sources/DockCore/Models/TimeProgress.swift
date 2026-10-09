import Foundation

/// A span of the calendar whose elapsed share the Time Progress widget shows.
public enum TimeProgressPeriod: String, CaseIterable, Hashable, Sendable {
    case year
    case month
    case week
    case day

    /// The calendar component one period of this kind spans.
    public var component: Calendar.Component {
        switch self {
        case .year: .year
        case .month: .month
        case .week: .weekOfYear
        case .day: .day
        }
    }

    /// The periods to show for the enabled set, in display order (longest first). The day
    /// stands in when nothing is enabled, so a tile is never empty.
    public static func shown(_ enabled: Set<TimeProgressPeriod>) -> [TimeProgressPeriod] {
        let shown = allCases.filter(enabled.contains)
        return shown.isEmpty ? [.day] : shown
    }
}

/// How far through a period a moment is: the time elapsed since the period began over the
/// period's whole length, both measured in real seconds. A year is 365 or 366 days long, a
/// month 28 to 31, and a day 23, 24, or 25 hours when the clocks change, so the share grows
/// linearly with the clock and reaches 100% exactly as the next period starts.
public struct TimeProgress: Hashable, Sendable {
    public let period: TimeProgressPeriod
    /// The moment the progress is for.
    public let date: Date
    /// When the period began.
    public let start: Date
    /// When the next period begins.
    public let end: Date
    /// One-based day within the period, e.g. day 282 of the year. Always 1 for `.day`.
    public let dayOrdinal: Int
    /// Days in the period: 365 or 366, 28 to 31, 7, or 1.
    public let dayCount: Int

    /// Nil only if `calendar` can't bound the period, which the Gregorian calendar always can.
    public init?(of period: TimeProgressPeriod, at date: Date, calendar: Calendar) {
        guard let interval = calendar.dateInterval(of: period.component, for: date),
            let dayCount = calendar.dateComponents([.day], from: interval.start, to: interval.end).day,
            let dayOrdinal = calendar.dateComponents([.day], from: interval.start, to: calendar.startOfDay(for: date))
                .day
        else { return nil }
        self.period = period
        self.date = date
        self.start = interval.start
        self.end = interval.end
        self.dayCount = max(1, dayCount)
        self.dayOrdinal = min(self.dayCount, max(1, dayOrdinal + 1))
    }

    /// Seconds since the period began.
    public var elapsed: TimeInterval { max(0, date.timeIntervalSince(start)) }

    /// Seconds until the next period begins.
    public var remaining: TimeInterval { max(0, end.timeIntervalSince(date)) }

    /// `elapsed` over the period's length, from 0 to 1. It never reaches 1 for a moment inside
    /// the period, since the next period begins at `end`.
    public var fraction: Double {
        let duration = end.timeIntervalSince(start)
        guard duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    /// `fraction` as a whole percentage, rounded down: 50% is only reached at the halfway
    /// point and 100% never shows, since by then the next period has begun.
    public var percent: Int { Int((fraction * 100).rounded(.down)) }

    /// `fraction` as a percentage with `fractionDigits` decimals, rounded down like `percent`,
    /// e.g. `"28.3%"`. Always uses a period as the decimal separator.
    public func percentText(fractionDigits: Int) -> String {
        let scale = pow(10, Double(fractionDigits))
        let value = (fraction * 100 * scale).rounded(.down) / scale
        return String(format: "%.\(fractionDigits)f%%", value)
    }

    /// Days left after today, as in "9 days left". Zero on the period's last day.
    public var daysLeft: Int { dayCount - dayOrdinal }

    /// Short text for what's left of the period: hours and minutes for a day, else days.
    public var remainingText: String {
        switch period {
        case .day:
            let minutes = Int((remaining / 60).rounded(.up))
            let hours = minutes / 60
            if hours == 0 { return "\(minutes) min left" }
            return minutes % 60 == 0 ? "\(hours) hr left" : "\(hours) hr \(minutes % 60) min left"
        case .week, .month, .year:
            switch daysLeft {
            case 0: return "Last day"
            case 1: return "1 day left"
            default: return "\(daysLeft) days left"
            }
        }
    }
}
