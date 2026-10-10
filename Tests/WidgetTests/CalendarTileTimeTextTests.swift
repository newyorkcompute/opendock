import Foundation
import SystemServices
import Testing

@testable import CalendarWidget

@MainActor
@Suite("Calendar tile time text")
struct CalendarTileTimeTextTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func event(startingIn seconds: TimeInterval, lasting duration: TimeInterval = 1_800) -> EventSummary {
        let start = now.addingTimeInterval(seconds)
        return EventSummary(
            id: "event", title: "Standup", startDate: start, endDate: start.addingTimeInterval(duration),
            isAllDay: false, calendarColorHex: "#FF0000", calendarTitle: "Work", location: nil, conferenceURL: nil)
    }

    @Test func anEventInProgressIsNow() {
        #expect(CalendarTileView.timeText(for: event(startingIn: -600), now: now) == "now")
        #expect(CalendarTileView.timeText(for: event(startingIn: 0), now: now) == "now")
    }

    @Test func minutesAreRoundedUpWithAFloorOfOne() {
        #expect(CalendarTileView.timeText(for: event(startingIn: 10), now: now) == "in 1 min")
        #expect(CalendarTileView.timeText(for: event(startingIn: 60), now: now) == "in 1 min")
        #expect(CalendarTileView.timeText(for: event(startingIn: 61), now: now) == "in 2 min")
        #expect(CalendarTileView.timeText(for: event(startingIn: 25 * 60), now: now) == "in 25 min")
        #expect(CalendarTileView.timeText(for: event(startingIn: 59 * 60), now: now) == "in 59 min")
    }

    @Test func anHourOrMoreAwayShowsTheClockTime() {
        for seconds in [59 * 60 + 1, 60 * 60, 5 * 60 * 60] {
            let event = event(startingIn: TimeInterval(seconds))
            let text = CalendarTileView.timeText(for: event, now: now)
            #expect(text == event.startDate.formatted(date: .omitted, time: .shortened))
            #expect(!text.hasPrefix("in "))
        }
    }
}
