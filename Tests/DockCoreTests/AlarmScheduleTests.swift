import Foundation
import Testing

@testable import DockCore

@Suite("Alarm schedule")
struct AlarmScheduleTests {
    /// A fixed calendar so the tests don't depend on the machine's zone or week start.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo") ?? .current
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    @Test func parsesTwentyFourHourTimes() {
        #expect(AlarmTime(parsing: "07:05") == AlarmTime(hour: 7, minute: 5))
        #expect(AlarmTime(parsing: "7:05") == AlarmTime(hour: 7, minute: 5))
        #expect(AlarmTime(parsing: " 23:59 ") == AlarmTime(hour: 23, minute: 59))
        #expect(AlarmTime(parsing: "00:00") == AlarmTime(hour: 0, minute: 0))
    }

    @Test(arguments: ["", "7", "24:00", "12:60", "7:5", "7:05 AM", "07:05:00", "seven", "-1:00"])
    func rejectsOtherTimes(_ string: String) {
        #expect(AlarmTime(parsing: string) == nil)
        #expect(!AlarmTime.isValid(string))
    }

    @Test func storageValueRoundTrips() {
        let time = AlarmTime(hour: 7, minute: 5)
        #expect(time.storageValue == "07:05")
        #expect(AlarmTime(parsing: time.storageValue) == time)
        #expect(AlarmTime(hour: 30, minute: 99) == AlarmTime(hour: 23, minute: 59), "clamped")
    }

    @Test func readsTheTimeOfDayOfADate() {
        let time = AlarmTime(of: date(2026, 10, 9, 18, 30), calendar: calendar)
        #expect(time == AlarmTime(hour: 18, minute: 30))
        #expect(time.date(on: date(2026, 10, 9, 3), calendar: calendar) == date(2026, 10, 9, 18, 30))
    }

    @Test func aOneOffAlarmFiresLaterTodayOrTomorrow() {
        let schedule = AlarmSchedule(time: AlarmTime(hour: 7, minute: 0))
        // Friday 9 October 2026.
        #expect(schedule.nextFiring(after: date(2026, 10, 9, 6, 59), calendar: calendar) == date(2026, 10, 9, 7))
        #expect(schedule.nextFiring(after: date(2026, 10, 9, 7, 0), calendar: calendar) == date(2026, 10, 10, 7))
        #expect(schedule.nextFiring(after: date(2026, 10, 9, 22), calendar: calendar) == date(2026, 10, 10, 7))
    }

    @Test func weekdayAlarmsSkipTheWeekend() {
        let schedule = AlarmSchedule(time: AlarmTime(hour: 7, minute: 0), repeats: .weekdays)
        // Friday evening → Monday.
        #expect(schedule.nextFiring(after: date(2026, 10, 9, 8), calendar: calendar) == date(2026, 10, 12, 7))
        // Saturday → Monday.
        #expect(schedule.nextFiring(after: date(2026, 10, 10, 8), calendar: calendar) == date(2026, 10, 12, 7))
    }

    @Test func weekendAlarmsWaitForSaturday() {
        let schedule = AlarmSchedule(time: AlarmTime(hour: 9, minute: 30), repeats: .weekends)
        // Monday → Saturday.
        #expect(schedule.nextFiring(after: date(2026, 10, 12, 10), calendar: calendar) == date(2026, 10, 17, 9, 30))
        // Saturday morning before the alarm → the same day.
        #expect(schedule.nextFiring(after: date(2026, 10, 17, 9), calendar: calendar) == date(2026, 10, 17, 9, 30))
        // Sunday after the alarm → next Saturday.
        #expect(schedule.nextFiring(after: date(2026, 10, 18, 10), calendar: calendar) == date(2026, 10, 24, 9, 30))
    }

    @Test func dailyAlarmsFireEveryDay() {
        let schedule = AlarmSchedule(time: AlarmTime(hour: 7, minute: 0), repeats: .daily)
        #expect(schedule.nextFiring(after: date(2026, 10, 10, 8), calendar: calendar) == date(2026, 10, 11, 7))
    }

    @Test func alarmsKeepTheirWallClockTimeAcrossADaylightSavingChange() {
        // Norway leaves summer time on 25 October 2026, so that day has 25 hours.
        let schedule = AlarmSchedule(time: AlarmTime(hour: 7, minute: 0), repeats: .daily)
        let next = schedule.nextFiring(after: date(2026, 10, 24, 8), calendar: calendar)
        #expect(next == date(2026, 10, 25, 7))
        #expect(next.map { AlarmTime(of: $0, calendar: calendar) } == AlarmTime(hour: 7, minute: 0))
    }

    @Test func repeatRulesAndTitles() {
        #expect(AlarmRepeat.weekdays.includes(weekday: 2))
        #expect(!AlarmRepeat.weekdays.includes(weekday: 1))
        #expect(AlarmRepeat.weekends.includes(weekday: 7))
        #expect(!AlarmRepeat.weekends.includes(weekday: 4))
        #expect(AlarmRepeat.once.includes(weekday: 1))
        #expect(AlarmRepeat.allCases.map(\.rawValue) == ["once", "daily", "weekdays", "weekends"])
        #expect(AlarmRepeat.daily.title == "Every day")
    }
}
