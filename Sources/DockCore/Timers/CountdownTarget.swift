import Foundation

/// The moment a countdown counts down to, as stored in settings and as read back.
public enum CountdownTarget {
    /// Reads a stored or hand-typed date. Accepts ISO 8601 with a zone
    /// (`"2026-12-25T08:00:00Z"`, `"2026-12-25T09:00:00+01:00"`), a local date and time
    /// (`"2026-12-25T09:00"` or `"2026-12-25T09:00:00"`), or a date alone (`"2026-12-25"`,
    /// midnight in `calendar`). Nil for anything else, including impossible dates.
    public static func parse(_ string: String, calendar: Calendar = .current) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let date = try? Date(trimmed, strategy: .iso8601) { return date }

        let parts = trimmed.split(separator: "T", maxSplits: 1, omittingEmptySubsequences: false)
        let dateFields = parts[0].split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
        guard dateFields.count == 3, let year = dateFields[0], let month = dateFields[1], let day = dateFields[2]
        else { return nil }

        var components = DateComponents(year: year, month: month, day: day, hour: 0, minute: 0, second: 0)
        if parts.count == 2 {
            let timeFields = parts[1].split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
            guard (2 ... 3).contains(timeFields.count), let hour = timeFields[0], let minute = timeFields[1]
            else { return nil }
            components.hour = hour
            components.minute = minute
            components.second = timeFields.count == 3 ? timeFields[2] : 0
        }
        guard let date = calendar.date(from: components) else { return nil }
        // `date(from:)` rolls impossible dates over (Feb 30 becomes Mar 2); reject those.
        let roundTrip = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard roundTrip.year == components.year, roundTrip.month == components.month, roundTrip.day == components.day,
            roundTrip.hour == components.hour, roundTrip.minute == components.minute,
            roundTrip.second == components.second
        else { return nil }
        return date
    }

    /// The form written to settings: ISO 8601 in UTC, to the second.
    public static func storageValue(for date: Date) -> String {
        date.formatted(.iso8601)
    }

    /// Whether `string` is empty (no date set) or something `parse` accepts.
    public static func isValid(_ string: String) -> Bool {
        string.isEmpty || parse(string) != nil
    }

    /// Time left until a target, broken down for display.
    public struct Remaining: Equatable, Sendable {
        public let days: Int
        public let hours: Int
        public let minutes: Int
        public let seconds: Int
        /// True once the target has passed; the components are then all zero.
        public let isPast: Bool

        public init(days: Int, hours: Int, minutes: Int, seconds: Int, isPast: Bool = false) {
            self.days = days
            self.hours = hours
            self.minutes = minutes
            self.seconds = seconds
            self.isPast = isPast
        }

        public static let past = Remaining(days: 0, hours: 0, minutes: 0, seconds: 0, isPast: true)

        public var totalSeconds: Int { ((days * 24 + hours) * 60 + minutes) * 60 + seconds }
    }

    /// Whole seconds from `now` to `target`, rounded up so the display reaches zero exactly
    /// when the target does.
    public static func remaining(until target: Date, from now: Date) -> Remaining {
        let total = target.timeIntervalSince(now)
        guard total > 0 else { return .past }
        let seconds = Int(total.rounded(.up))
        return Remaining(
            days: seconds / 86400, hours: seconds % 86400 / 3600, minutes: seconds % 3600 / 60, seconds: seconds % 60)
    }
}
