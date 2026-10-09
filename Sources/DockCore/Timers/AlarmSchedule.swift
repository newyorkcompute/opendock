import Foundation

/// A time of day for an alarm, stored in `dock.json` as 24-hour `"HH:mm"`.
public struct AlarmTime: Hashable, Sendable {
    public let hour: Int
    public let minute: Int

    /// Clamps into 0...23 and 0...59.
    public init(hour: Int, minute: Int) {
        self.hour = min(23, max(0, hour))
        self.minute = min(59, max(0, minute))
    }

    /// Parses `"HH:mm"` (a single-digit hour is fine too). Nil for anything else.
    public init?(parsing string: String) {
        let parts = string.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1].count == 2,
            let hour = Int(parts[0]), let minute = Int(parts[1]),
            (0 ... 23).contains(hour), (0 ... 59).contains(minute)
        else { return nil }
        self.init(hour: hour, minute: minute)
    }

    /// The form stored in settings: `"07:05"`.
    public var storageValue: String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// Whether `string` is something `init(parsing:)` accepts.
    public static func isValid(_ string: String) -> Bool {
        AlarmTime(parsing: string) != nil
    }

    /// This time of day on the day containing `day`, in `calendar`.
    public func date(on day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: calendar.startOfDay(for: day))
    }

    /// The time of day of `date`.
    public init(of date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }
}

/// Which days an alarm goes off. The raw values are stored in settings.
public enum AlarmRepeat: String, CaseIterable, Sendable {
    /// The next time the clock reaches the alarm time, then the alarm turns itself off.
    case once
    case daily
    case weekdays
    case weekends

    /// Whether the alarm fires on `weekday`, in `Calendar`'s numbering (1 is Sunday).
    public func includes(weekday: Int) -> Bool {
        switch self {
        case .once, .daily: true
        case .weekdays: (2 ... 6).contains(weekday)
        case .weekends: weekday == 1 || weekday == 7
        }
    }

    public var title: String {
        switch self {
        case .once: "Once"
        case .daily: "Every day"
        case .weekdays: "Weekdays"
        case .weekends: "Weekends"
        }
    }
}

/// When an alarm goes off: a time of day plus which days.
public struct AlarmSchedule: Hashable, Sendable {
    public var time: AlarmTime
    public var repeats: AlarmRepeat

    public init(time: AlarmTime, repeats: AlarmRepeat = .once) {
        self.time = time
        self.repeats = repeats
    }

    /// The first moment strictly after `now` that the alarm should fire. Nil only if the
    /// calendar can't produce one.
    public func nextFiring(after now: Date, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        for offset in 0 ..< 8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                let candidate = time.date(on: day, calendar: calendar)
            else { continue }
            guard candidate > now, repeats.includes(weekday: calendar.component(.weekday, from: candidate)) else {
                continue
            }
            return candidate
        }
        return nil
    }
}
