import Foundation
import Testing

@testable import DockCore

@Suite("Countdown target")
struct CountdownTargetTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo") ?? .current
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0)
        -> Date
    {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))
            ?? .distantPast
    }

    @Test func parsesISO8601WithAZone() {
        #expect(CountdownTarget.parse("2026-12-25T08:00:00Z", calendar: calendar) == date(2026, 12, 25, 9))
        #expect(CountdownTarget.parse("2026-12-25T09:00:00+01:00", calendar: calendar) == date(2026, 12, 25, 9))
    }

    @Test func parsesLocalDatesAndTimes() {
        #expect(CountdownTarget.parse("2026-12-25", calendar: calendar) == date(2026, 12, 25))
        #expect(CountdownTarget.parse("2026-12-25T18:30", calendar: calendar) == date(2026, 12, 25, 18, 30))
        #expect(CountdownTarget.parse("2026-12-25T18:30:15", calendar: calendar) == date(2026, 12, 25, 18, 30, 15))
        #expect(CountdownTarget.parse("  2026-01-01 ", calendar: calendar) == date(2026, 1, 1))
    }

    @Test(arguments: ["", "tomorrow", "2026-02-30", "2026-13-01", "2026-12-25T25:00", "2026-12-25T18", "25/12/2026"])
    func rejectsWhatItCannotRead(_ string: String) {
        #expect(CountdownTarget.parse(string, calendar: calendar) == nil)
    }

    @Test func emptyIsValidAsUnsetButGarbageIsNot() {
        #expect(CountdownTarget.isValid(""))
        #expect(CountdownTarget.isValid("2026-12-25"))
        #expect(!CountdownTarget.isValid("soon"))
    }

    @Test func storageValueRoundTrips() {
        let target = date(2026, 12, 25, 9)
        let stored = CountdownTarget.storageValue(for: target)
        #expect(stored == "2026-12-25T08:00:00Z")
        #expect(CountdownTarget.parse(stored, calendar: calendar) == target)
    }

    @Test func remainingBreaksDownAndRoundsUp() {
        let now = date(2026, 10, 9, 12)
        let remaining = CountdownTarget.remaining(until: date(2026, 10, 11, 15, 4, 5), from: now)
        #expect(remaining == CountdownTarget.Remaining(days: 2, hours: 3, minutes: 4, seconds: 5))
        #expect(remaining.totalSeconds == 2 * 86400 + 3 * 3600 + 4 * 60 + 5)
        #expect(!remaining.isPast)
        #expect(CountdownTarget.remaining(until: now + 0.2, from: now).seconds == 1, "rounds up to the second")
    }

    @Test func pastTargetsAreDone() {
        let now = date(2026, 10, 9, 12)
        #expect(CountdownTarget.remaining(until: now, from: now) == .past)
        #expect(CountdownTarget.remaining(until: now - 5, from: now).isPast)
        #expect(CountdownTarget.Remaining.past.totalSeconds == 0)
    }
}
