import Foundation

/// Text for the time widgets' tiles and popovers. Locale-independent on purpose: these
/// are digits and short units that have to stay the same width while they tick.
public enum TimerFormatting {
    /// Seconds left as `"25:00"` or `"1:05:09"`, rounded up so a fresh 25-minute timer
    /// reads 25:00 and only reaches 0:00 when it's done. Never negative.
    public static func countdown(_ seconds: TimeInterval) -> String {
        clock(Int(max(0, seconds).rounded(.up)))
    }

    /// Elapsed time as `"00:12"` or `"1:02:03"`, with tenths (`"00:12.3"`) when asked.
    /// Rounded down, as a stopwatch is.
    public static func stopwatch(_ seconds: TimeInterval, tenths: Bool) -> String {
        // Whole tenths first, so 12.3 s doesn't come out as 12.2 through floating point.
        let totalTenths = Int((max(0, seconds) * 10 + 1e-6).rounded(.down))
        let whole = totalTenths / 10
        var text = whole >= 3600 ? clock(whole) : String(format: "%02d:%02d", whole / 60, whole % 60)
        if tenths {
            text += ".\(totalTenths % 10)"
        }
        return text
    }

    /// `"m:ss"` under an hour, `"h:mm:ss"` from then on.
    static func clock(_ seconds: Int) -> String {
        let total = max(0, seconds)
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Short form for a tile: `"12d 4h"` with days, `"4:05:09"` within a day, `"Now"` once past.
    public static func compactCountdown(_ remaining: CountdownTarget.Remaining) -> String {
        if remaining.isPast { return "Now" }
        if remaining.days > 0 { return "\(remaining.days)d \(remaining.hours)h" }
        return clock(remaining.totalSeconds)
    }

    /// Long form for a popover: `"12 days 4 hours"`, `"4 hours 5 minutes"`,
    /// `"5 minutes 9 seconds"`, `"9 seconds"`, or `"Now"`. The two largest non-zero units.
    public static func longCountdown(_ remaining: CountdownTarget.Remaining) -> String {
        if remaining.isPast { return "Now" }
        let units: [(Int, String)] = [
            (remaining.days, "day"), (remaining.hours, "hour"), (remaining.minutes, "minute"),
            (remaining.seconds, "second"),
        ]
        guard let first = units.firstIndex(where: { $0.0 > 0 }) else { return "Now" }
        return units[first ..< min(units.count, first + 2)]
            .filter { $0.0 > 0 }
            .map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }
            .joined(separator: " ")
    }

    /// Which day a moment falls on, relative to `now`: `"Today"`, `"Tomorrow"`, or the
    /// calendar's short weekday name (`"Mon"`) further out.
    public static func dayLabel(for date: Date, now: Date, calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        default: return calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
        }
    }

    /// Minutes as `"25 min"`, `"1 hr"`, `"1 hr 30 min"`, for settings summaries.
    public static func minutes(_ minutes: Int) -> String {
        let total = max(0, minutes)
        if total < 60 { return "\(total) min" }
        return total.isMultiple(of: 60) ? "\(total / 60) hr" : "\(total / 60) hr \(total % 60) min"
    }
}
