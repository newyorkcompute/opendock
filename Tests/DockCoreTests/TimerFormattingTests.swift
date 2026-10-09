import Foundation
import Testing

@testable import DockCore

@Suite("Timer formatting")
struct TimerFormattingTests {
    @Test func countdownRoundsUpToTheSecond() {
        #expect(TimerFormatting.countdown(25 * 60) == "25:00")
        #expect(TimerFormatting.countdown(24 * 60 + 59.2) == "25:00")
        #expect(TimerFormatting.countdown(59) == "0:59")
        #expect(TimerFormatting.countdown(0.4) == "0:01")
        #expect(TimerFormatting.countdown(0) == "0:00")
        #expect(TimerFormatting.countdown(-10) == "0:00")
        #expect(TimerFormatting.countdown(3600 + 5 * 60 + 9) == "1:05:09")
    }

    @Test func stopwatchRoundsDownAndPadsMinutes() {
        #expect(TimerFormatting.stopwatch(0, tenths: false) == "00:00")
        #expect(TimerFormatting.stopwatch(12.99, tenths: false) == "00:12")
        #expect(TimerFormatting.stopwatch(12.3, tenths: true) == "00:12.3")
        #expect(TimerFormatting.stopwatch(8.2, tenths: true) == "00:08.2")
        #expect(TimerFormatting.stopwatch(754.07, tenths: true) == "12:34.0")
        #expect(TimerFormatting.stopwatch(3723.4, tenths: true) == "1:02:03.4")
        #expect(TimerFormatting.stopwatch(3723.4, tenths: false) == "1:02:03")
        #expect(TimerFormatting.stopwatch(-1, tenths: true) == "00:00.0")
    }

    @Test func compactCountdown() {
        #expect(TimerFormatting.compactCountdown(.init(days: 12, hours: 4, minutes: 3, seconds: 2)) == "12d 4h")
        #expect(TimerFormatting.compactCountdown(.init(days: 1, hours: 0, minutes: 3, seconds: 2)) == "1d 0h")
        #expect(TimerFormatting.compactCountdown(.init(days: 0, hours: 4, minutes: 5, seconds: 9)) == "4:05:09")
        #expect(TimerFormatting.compactCountdown(.init(days: 0, hours: 0, minutes: 5, seconds: 9)) == "5:09")
        #expect(TimerFormatting.compactCountdown(.past) == "Now")
    }

    @Test func longCountdownNamesTheTwoLargestUnits() {
        #expect(TimerFormatting.longCountdown(.init(days: 12, hours: 4, minutes: 3, seconds: 2)) == "12 days 4 hours")
        #expect(TimerFormatting.longCountdown(.init(days: 1, hours: 0, minutes: 3, seconds: 2)) == "1 day")
        #expect(TimerFormatting.longCountdown(.init(days: 0, hours: 1, minutes: 1, seconds: 2)) == "1 hour 1 minute")
        #expect(
            TimerFormatting.longCountdown(.init(days: 0, hours: 0, minutes: 5, seconds: 9)) == "5 minutes 9 seconds")
        #expect(TimerFormatting.longCountdown(.init(days: 0, hours: 0, minutes: 0, seconds: 1)) == "1 second")
        #expect(TimerFormatting.longCountdown(.init(days: 0, hours: 0, minutes: 0, seconds: 0)) == "Now")
        #expect(TimerFormatting.longCountdown(.past) == "Now")
    }

    @Test func dayLabels() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo") ?? .current
        calendar.locale = Locale(identifier: "en_US")
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 12)) ?? .distantPast
        let day: (Int, Int) -> Date = { d, h in
            calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h)) ?? .distantPast
        }
        #expect(TimerFormatting.dayLabel(for: day(9, 23), now: now, calendar: calendar) == "Today")
        #expect(TimerFormatting.dayLabel(for: day(10, 0), now: now, calendar: calendar) == "Tomorrow")
        #expect(
            TimerFormatting.dayLabel(for: day(12, 7), now: now, calendar: calendar) == calendar.shortWeekdaySymbols[1],
            "Monday 12 October")
    }

    @Test func minutesAsHoursAndMinutes() {
        #expect(TimerFormatting.minutes(25) == "25 min")
        #expect(TimerFormatting.minutes(60) == "1 hr")
        #expect(TimerFormatting.minutes(90) == "1 hr 30 min")
        #expect(TimerFormatting.minutes(-5) == "0 min")
    }
}
