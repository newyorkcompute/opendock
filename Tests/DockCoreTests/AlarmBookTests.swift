import Foundation
import Testing

@testable import DockCore

@Suite("Alarm book")
struct AlarmBookTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo") ?? .current
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0
    ) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))
            ?? .distantPast
    }

    private let id = UUID()
    private let other = UUID()
    private let seven = AlarmSchedule(time: AlarmTime(hour: 7, minute: 0))
    private let sevenDaily = AlarmSchedule(time: AlarmTime(hour: 7, minute: 0), repeats: .daily)
    private let halfPastSeven = AlarmSchedule(time: AlarmTime(hour: 7, minute: 30))

    /// A book with `id` set to `schedule` just before 7:00 on Friday 9 October 2026, rung
    /// at 7:00 when `ringing`.
    private func book(_ schedule: AlarmSchedule, ringDuration: TimeInterval = 90, ringing: Bool) -> AlarmBook {
        var book = AlarmBook(ringDuration: ringDuration)
        book.set(id, schedule: schedule, now: date(2026, 10, 9, 6, 59), calendar: calendar)
        if ringing { _ = book.advance(to: date(2026, 10, 9, 7), calendar: calendar) }
        return book
    }

    @Test func startsEmpty() {
        let book = AlarmBook()
        #expect(book.ids.isEmpty)
        #expect(book.armed.isEmpty)
        #expect(book.ringing.isEmpty)
        #expect(book.nextDeadline == nil)
        #expect(book.ringDuration == 90)
    }

    @Test func settingAnAlarmArmsItsNextFiring() {
        let book = book(seven, ringing: false)
        #expect(book.isSet(id))
        #expect(book.schedule(for: id) == seven)
        #expect(book.armed[id] == date(2026, 10, 9, 7))
        #expect(book.nextDeadline == date(2026, 10, 9, 7))
        #expect(!book.isRinging(id))
    }

    @Test func settingTheSameScheduleAgainKeepsAPendingSnooze() {
        var book = book(seven, ringing: true)
        let snoozed = book.snooze(id, minutes: 9, now: date(2026, 10, 9, 7, 1))
        #expect(snoozed == date(2026, 10, 9, 7, 10))

        // The store re-syncs with the same time and repeat (the label changed, say).
        book.set(id, schedule: seven, now: date(2026, 10, 9, 7, 2), calendar: calendar)
        #expect(book.armed[id] == date(2026, 10, 9, 7, 10), "the snooze stands")

        // A new time replaces it.
        let eight = AlarmSchedule(time: AlarmTime(hour: 8, minute: 0))
        book.set(id, schedule: eight, now: date(2026, 10, 9, 7, 2), calendar: calendar)
        #expect(book.armed[id] == date(2026, 10, 9, 8))
    }

    @Test func changingTheScheduleOfARingingAlarmDoesNotInterruptIt() {
        var book = book(seven, ringing: true)
        book.set(id, schedule: sevenDaily, now: date(2026, 10, 9, 7, 0, 30), calendar: calendar)
        #expect(book.isRinging(id))
        #expect(book.armed[id] == nil)
        // Stopping applies the new schedule.
        let outcome = book.stop(id, now: date(2026, 10, 9, 7, 1), calendar: calendar)
        #expect(outcome == .rearmed(date(2026, 10, 10, 7)))
    }

    @Test func advancingPastTheTimeRingsTheAlarmOnce() {
        var book = book(seven, ringing: false)
        let early = book.advance(to: date(2026, 10, 9, 6, 59, 59), calendar: calendar)
        #expect(early.isEmpty)
        let onTime = book.advance(to: date(2026, 10, 9, 7), calendar: calendar)
        #expect(onTime == [.rang(id)])
        #expect(book.isRinging(id))
        #expect(book.ringing[id] == date(2026, 10, 9, 7))
        #expect(book.armed[id] == nil, "a ringing alarm has no next firing until it's stopped")
        #expect(book.nextDeadline == date(2026, 10, 9, 7, 1, 30), "when it gives up")
        let later = book.advance(to: date(2026, 10, 9, 7, 0, 10), calendar: calendar)
        #expect(later.isEmpty, "still ringing")
    }

    @Test func aOneOffAlarmFinishesWhenStopped() {
        var book = book(seven, ringing: true)
        let outcome = book.stop(id, now: date(2026, 10, 9, 7, 0, 20), calendar: calendar)
        #expect(outcome == .finished)
        #expect(!book.isRinging(id))
        #expect(book.armed[id] == nil)
        #expect(book.isSet(id), "its settings turn it off; until the store says so it stays in the book")
        #expect(book.nextDeadline == nil)
    }

    @Test func aRepeatingAlarmRearmsWhenStopped() {
        var book = book(sevenDaily, ringing: true)
        let outcome = book.stop(id, now: date(2026, 10, 9, 7, 0, 20), calendar: calendar)
        #expect(outcome == .rearmed(date(2026, 10, 10, 7)))
        #expect(book.armed[id] == date(2026, 10, 10, 7))
    }

    @Test func stoppingOrSnoozingAnAlarmThatIsNotRingingDoesNothing() {
        var book = book(seven, ringing: false)
        let stopped = book.stop(id, now: date(2026, 10, 9, 6, 59, 30), calendar: calendar)
        let snoozed = book.snooze(id, minutes: 5, now: date(2026, 10, 9, 6, 59, 30))
        let unknown = book.stop(other, now: date(2026, 10, 9, 7), calendar: calendar)
        #expect(stopped == nil)
        #expect(snoozed == nil)
        #expect(unknown == nil)
        #expect(book.armed[id] == date(2026, 10, 9, 7))
    }

    @Test func snoozeWaitsAtLeastAMinute() {
        var book = book(seven, ringing: true)
        let snoozed = book.snooze(id, minutes: 0, now: date(2026, 10, 9, 7, 0, 30))
        #expect(snoozed == date(2026, 10, 9, 7, 1, 30))
        #expect(!book.isRinging(id))
        #expect(book.nextDeadline == date(2026, 10, 9, 7, 1, 30))
        let again = book.advance(to: date(2026, 10, 9, 7, 1, 30), calendar: calendar)
        #expect(again == [.rang(id)], "rings again")
    }

    @Test func anUnansweredAlarmGivesUpAfterTheRingDuration() {
        var book = book(seven, ringDuration: 60, ringing: true)
        let before = book.advance(to: date(2026, 10, 9, 7, 0, 59), calendar: calendar)
        #expect(before.isEmpty)
        let after = book.advance(to: date(2026, 10, 9, 7, 1), calendar: calendar)
        #expect(after == [.timedOut(id, .finished)])
        #expect(!book.isRinging(id))
        #expect(book.nextDeadline == nil)
    }

    @Test func anUnansweredRepeatingAlarmGivesUpAndRearms() {
        var book = book(sevenDaily, ringDuration: 60, ringing: true)
        let events = book.advance(to: date(2026, 10, 9, 7, 5), calendar: calendar)
        #expect(events == [.timedOut(id, .rearmed(date(2026, 10, 10, 7)))])
        #expect(book.armed[id] == date(2026, 10, 10, 7))
    }

    @Test func aLongJumpInTimeRingsAndDoesNotTimeOutInOneStep() {
        // The Mac slept through the alarm time: it rings on wake, then gets its full ring duration.
        var book = book(seven, ringDuration: 60, ringing: false)
        let wake = date(2026, 10, 9, 9)
        let events = book.advance(to: wake, calendar: calendar)
        #expect(events == [.rang(id)])
        #expect(book.ringing[id] == wake)
        #expect(book.nextDeadline == wake.addingTimeInterval(60))
    }

    @Test func removingAnAlarmReportsWhetherItWasRinging() {
        var quiet = book(seven, ringing: false)
        let wasQuiet = quiet.remove(id)
        #expect(!wasQuiet, "set but quiet")
        #expect(!quiet.isSet(id))
        #expect(quiet.armed[id] == nil)

        var loud = book(seven, ringing: true)
        let wasRinging = loud.remove(id)
        #expect(wasRinging)
        #expect(loud.ringing.isEmpty)
        let again = loud.remove(id)
        #expect(!again, "already gone")
    }

    @Test func removingAllExceptSomeKeepsThoseAndReportsTheRingingOnes() {
        var book = book(seven, ringing: false)
        let third = UUID()
        book.set(other, schedule: seven, now: date(2026, 10, 9, 6, 59), calendar: calendar)
        book.set(third, schedule: sevenDaily, now: date(2026, 10, 9, 6, 59), calendar: calendar)
        _ = book.advance(to: date(2026, 10, 9, 7), calendar: calendar)
        #expect(book.ringing.count == 3)

        // The profile switched: only `id` is in the new one.
        let removed = book.removeAll(except: [id])
        #expect(Set(removed) == [other, third])
        #expect(book.ids == [id])
        #expect(book.isRinging(id))
        let nothing = book.removeAll(except: [id])
        #expect(nothing.isEmpty, "nothing left to remove")
        let last = book.removeAll(except: [])
        #expect(last == [id])
        #expect(book == AlarmBook())
    }

    @Test func theNextDeadlineIsTheEarliestOfFiringsAndTimeouts() {
        var book = book(seven, ringing: false)
        book.set(other, schedule: halfPastSeven, now: date(2026, 10, 9, 6, 59), calendar: calendar)
        #expect(book.nextDeadline == date(2026, 10, 9, 7))
        let rang = book.advance(to: date(2026, 10, 9, 7), calendar: calendar)
        #expect(rang == [.rang(id)])
        #expect(book.nextDeadline == date(2026, 10, 9, 7, 1, 30), "the first alarm gives up before the second rings")
        let snoozed = book.snooze(id, minutes: 60, now: date(2026, 10, 9, 7, 0, 10))
        #expect(snoozed == date(2026, 10, 9, 8, 0, 10))
        #expect(book.nextDeadline == date(2026, 10, 9, 7, 30))
    }

    @Test func alarmsRingInTimeOrderWhenSeveralAreDue() {
        var book = AlarmBook()
        book.set(other, schedule: halfPastSeven, now: date(2026, 10, 9, 6, 59), calendar: calendar)
        book.set(id, schedule: seven, now: date(2026, 10, 9, 6, 59), calendar: calendar)
        let events = book.advance(to: date(2026, 10, 9, 8), calendar: calendar)
        #expect(events == [.rang(id), .rang(other)])
    }
}
