import Foundation
import Testing

@testable import DockCore

@Suite("Time progress")
struct TimeProgressTests {
    /// A Gregorian calendar in `zone`, with Monday as the first day of the week unless told otherwise.
    private func calendar(_ zone: String, firstWeekday: Int = 2) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0,
        in calendar: Calendar
    ) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    private func progress(
        _ period: TimeProgressPeriod, _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0,
        _ second: Int = 0, in calendar: Calendar
    ) -> TimeProgress {
        TimeProgress(
            of: period, at: date(year, month, day, hour, minute, second, in: calendar), calendar: calendar)!
    }

    private func close(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 1e-9
    }

    // MARK: Fractions

    @Test func noonIsHalfwayThroughTheDay() {
        let calendar = calendar("UTC")
        let day = progress(.day, 2026, 10, 9, 12, in: calendar)
        #expect(day.fraction == 0.5)
        #expect(day.percent == 50)
        #expect(day.elapsed == 12 * 3600)
        #expect(day.remaining == 12 * 3600)
        #expect(day.dayOrdinal == 1)
        #expect(day.dayCount == 1)
        #expect(day.start == date(2026, 10, 9, in: calendar))
        #expect(day.end == date(2026, 10, 10, in: calendar))
    }

    @Test func periodsStartAtZero() {
        // January 1, 2029 is a Monday, so every period begins at once.
        let calendar = calendar("UTC")
        let moment = date(2029, 1, 1, in: calendar)
        for period in TimeProgressPeriod.allCases {
            let progress = TimeProgress(of: period, at: moment, calendar: calendar)!
            #expect(progress.start == moment, "\(period)")
            #expect(progress.fraction == 0, "\(period)")
            #expect(progress.percent == 0, "\(period)")
            #expect(progress.elapsed == 0, "\(period)")
        }
        let year = TimeProgress(of: .year, at: moment, calendar: calendar)!
        #expect(year.end == date(2030, 1, 1, in: calendar))
        #expect(year.dayOrdinal == 1)
        #expect(year.dayCount == 365)
    }

    @Test func fractionNeverReachesOneInsideThePeriod() {
        let calendar = calendar("UTC")
        let lastSecond = progress(.day, 2026, 10, 9, 23, 59, 59, in: calendar)
        #expect(lastSecond.fraction < 1)
        #expect(lastSecond.percent == 99)
        let lastDay = progress(.year, 2026, 12, 31, 23, 59, in: calendar)
        #expect(lastDay.percent == 99)
        #expect(lastDay.dayOrdinal == 365)
    }

    @Test func leapYearHas366Days() {
        let calendar = calendar("UTC")
        let leap = progress(.year, 2024, 3, 1, in: calendar)
        #expect(leap.dayCount == 366)
        #expect(leap.dayOrdinal == 61)
        #expect(close(leap.fraction, 60 / 366))
        #expect(leap.daysLeft == 305)

        let common = progress(.year, 2023, 3, 1, in: calendar)
        #expect(common.dayCount == 365)
        #expect(common.dayOrdinal == 60)
        #expect(close(common.fraction, 59 / 365))
    }

    @Test func februaryInALeapYear() {
        let calendar = calendar("UTC")
        let leap = progress(.month, 2024, 2, 15, 12, in: calendar)
        #expect(leap.dayCount == 29)
        #expect(leap.dayOrdinal == 15)
        #expect(leap.fraction == 0.5)
        #expect(leap.percent == 50)

        let common = progress(.month, 2023, 2, 15, in: calendar)
        #expect(common.dayCount == 28)
        #expect(common.fraction == 0.5)
    }

    @Test func monthFractionFollowsElapsedTime() {
        let calendar = calendar("UTC")
        let october = progress(.month, 2026, 10, 9, 12, in: calendar)
        #expect(october.dayCount == 31)
        #expect(october.dayOrdinal == 9)
        #expect(close(october.fraction, 8.5 / 31))
        #expect(october.percent == 27)
    }

    // MARK: Daylight saving time

    @Test func springForwardDayIs23HoursLong() {
        // US clocks skip 2:00-3:00 on March 8, 2026.
        let calendar = calendar("America/New_York")
        let day = progress(.day, 2026, 3, 8, 12, in: calendar)
        #expect(day.end.timeIntervalSince(day.start) == 23 * 3600)
        #expect(day.elapsed == 11 * 3600)
        #expect(day.remaining == 12 * 3600)
        #expect(close(day.fraction, 11 / 23))
        #expect(day.percent == 47)
        #expect(day.remainingText == "12 hr left")
    }

    @Test func fallBackDayIs25HoursLong() {
        // US clocks repeat 1:00-2:00 on November 1, 2026.
        let calendar = calendar("America/New_York")
        let day = progress(.day, 2026, 11, 1, 12, in: calendar)
        #expect(day.end.timeIntervalSince(day.start) == 25 * 3600)
        #expect(day.elapsed == 13 * 3600)
        #expect(close(day.fraction, 13 / 25))
        #expect(day.percent == 52)
    }

    @Test func monthContainingATimeChangeCountsCalendarDays() {
        // March 2026 in New York is 31 days minus an hour; the day ordinal still comes from the calendar.
        let calendar = calendar("America/New_York")
        let march = progress(.month, 2026, 3, 16, 12, in: calendar)
        #expect(march.dayCount == 31)
        #expect(march.dayOrdinal == 16)
        #expect(march.end.timeIntervalSince(march.start) == Double(31 * 24 - 1) * 3600)
        #expect(close(march.fraction, Double(15 * 24 + 11) / Double(31 * 24 - 1)))
        #expect(march.daysLeft == 15)
    }

    // MARK: Weeks and time zones

    @Test func weekStartsOnTheCalendarsFirstWeekday() {
        // October 9, 2026 is a Friday.
        let mondayFirst = calendar("UTC", firstWeekday: 2)
        let week = progress(.week, 2026, 10, 9, in: mondayFirst)
        #expect(week.start == date(2026, 10, 5, in: mondayFirst))
        #expect(week.end == date(2026, 10, 12, in: mondayFirst))
        #expect(week.dayCount == 7)
        #expect(week.dayOrdinal == 5)
        #expect(close(week.fraction, 4 / 7))
        #expect(week.daysLeft == 2)

        let sundayFirst = calendar("UTC", firstWeekday: 1)
        let sundayWeek = progress(.week, 2026, 10, 9, in: sundayFirst)
        #expect(sundayWeek.start == date(2026, 10, 4, in: sundayFirst))
        #expect(sundayWeek.dayOrdinal == 6)
        #expect(close(sundayWeek.fraction, 5 / 7))
    }

    @Test func sameInstantDiffersByTimeZone() {
        let instant = date(2026, 10, 9, 23, 30, in: calendar("UTC"))
        let london = TimeProgress(of: .day, at: instant, calendar: calendar("UTC"))!
        #expect(close(london.fraction, 23.5 / 24))
        #expect(london.percent == 97)

        let tokyo = TimeProgress(of: .day, at: instant, calendar: calendar("Asia/Tokyo"))!
        #expect(close(tokyo.fraction, 8.5 / 24))
        #expect(tokyo.percent == 35)

        let tokyoMonth = TimeProgress(of: .month, at: instant, calendar: calendar("Asia/Tokyo"))!
        #expect(tokyoMonth.dayOrdinal == 10)
        let londonMonth = TimeProgress(of: .month, at: instant, calendar: calendar("UTC"))!
        #expect(londonMonth.dayOrdinal == 9)
    }

    // MARK: Text

    @Test func percentRoundsDown() {
        let calendar = calendar("UTC")
        let lastSecond = progress(.day, 2026, 10, 9, 23, 59, 59, in: calendar)
        #expect(lastSecond.percentText(fractionDigits: 1) == "99.9%")
        #expect(lastSecond.percentText(fractionDigits: 0) == "99%")
        let midnight = progress(.day, 2026, 10, 9, in: calendar)
        #expect(midnight.percentText(fractionDigits: 1) == "0.0%")
        // 8.5 / 31 = 27.419...%
        let october = progress(.month, 2026, 10, 9, 12, in: calendar)
        #expect(october.percentText(fractionDigits: 1) == "27.4%")
        #expect(october.percentText(fractionDigits: 2) == "27.41%")
    }

    @Test func remainingTextForTheDay() {
        let calendar = calendar("UTC")
        #expect(progress(.day, 2026, 10, 9, 12, in: calendar).remainingText == "12 hr left")
        #expect(progress(.day, 2026, 10, 9, 22, 15, in: calendar).remainingText == "1 hr 45 min left")
        #expect(progress(.day, 2026, 10, 9, 23, 30, in: calendar).remainingText == "30 min left")
        #expect(progress(.day, 2026, 10, 9, 23, 59, 30, in: calendar).remainingText == "1 min left")
        #expect(progress(.day, 2026, 10, 9, in: calendar).remainingText == "24 hr left")
    }

    @Test func remainingTextForLongerPeriods() {
        let calendar = calendar("UTC")
        #expect(progress(.month, 2026, 10, 9, in: calendar).remainingText == "22 days left")
        #expect(progress(.month, 2026, 10, 30, in: calendar).remainingText == "1 day left")
        #expect(progress(.month, 2026, 10, 31, 23, in: calendar).remainingText == "Last day")
        #expect(progress(.year, 2026, 1, 1, in: calendar).remainingText == "364 days left")
        #expect(progress(.year, 2026, 12, 31, in: calendar).remainingText == "Last day")
        #expect(progress(.week, 2026, 10, 9, in: calendar).remainingText == "2 days left")
    }

    // MARK: Selection

    @Test func shownPeriodsKeepDisplayOrderAndFallBackToTheDay() {
        #expect(TimeProgressPeriod.shown([]) == [.day])
        #expect(TimeProgressPeriod.shown([.day, .year]) == [.year, .day])
        #expect(TimeProgressPeriod.shown([.week]) == [.week])
        #expect(TimeProgressPeriod.shown(Set(TimeProgressPeriod.allCases)) == [.year, .month, .week, .day])
    }

    @Test func componentsMatchThePeriods() {
        #expect(TimeProgressPeriod.year.component == .year)
        #expect(TimeProgressPeriod.month.component == .month)
        #expect(TimeProgressPeriod.week.component == .weekOfYear)
        #expect(TimeProgressPeriod.day.component == .day)
    }
}
