import Foundation
import Testing

@testable import DockCore

/// Friday 2026-10-09 12:00 UTC, in a fixed Gregorian/UTC/en_US calendar so the tests don't
/// depend on the machine running them.
private let now = Date(timeIntervalSince1970: 1_791_547_200)
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US")
    return calendar
}()
private let locale = Locale(identifier: "en_US")

private let groceries = ReminderList(id: "groceries", title: "Groceries", colorHex: "#FF9500")
private let work = ReminderList(id: "work", title: "Work", colorHex: "#0A84FF")

/// A reminder in `list`, due `days` from today at `hour` (or all day when `hour` is nil).
private func reminder(
    _ title: String,
    in list: ReminderList = groceries,
    days: Int? = nil,
    hour: Int? = nil,
    priority: ReminderItem.Priority = .none,
    id: String? = nil
) -> ReminderItem {
    var dueDate: Date?
    if let days {
        let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))!
        dueDate = hour.map { calendar.date(bySettingHour: $0, minute: 0, second: 0, of: day)! } ?? day
    }
    return ReminderItem(
        id: id ?? title, title: title, listID: list.id, listTitle: list.title, listColorHex: list.colorHex,
        dueDate: dueDate, dueDateHasTime: hour != nil, priority: priority)
}

@Suite("Reminder items")
struct ReminderItemTests {
    @Test func mapsEventKitPriorities() {
        #expect(ReminderItem.Priority(eventKitPriority: 0) == .none)
        #expect(ReminderItem.Priority(eventKitPriority: 1) == .high)
        #expect(ReminderItem.Priority(eventKitPriority: 4) == .high)
        #expect(ReminderItem.Priority(eventKitPriority: 5) == .medium)
        #expect(ReminderItem.Priority(eventKitPriority: 6) == .low)
        #expect(ReminderItem.Priority(eventKitPriority: 9) == .low)
        #expect(ReminderItem.Priority(eventKitPriority: 12) == .none)
        #expect(ReminderItem.Priority.allCases == [.high, .medium, .low, .none])
        #expect(ReminderItem.Priority.allCases == ReminderItem.Priority.allCases.sorted())
    }

    @Test func dueStateFollowsTheClockWhenTheReminderHasATime() {
        #expect(reminder("a", days: -1, hour: 10).dueState(at: now, calendar: calendar) == .overdue)
        #expect(reminder("a", days: 0, hour: 9).dueState(at: now, calendar: calendar) == .overdue)
        #expect(reminder("a", days: 0, hour: 12).dueState(at: now, calendar: calendar) == .today)
        #expect(reminder("a", days: 0, hour: 17).dueState(at: now, calendar: calendar) == .today)
        #expect(reminder("a", days: 1, hour: 9).dueState(at: now, calendar: calendar) == .upcoming)
    }

    @Test func dueStateFollowsTheDayWhenTheReminderHasNoTime() {
        // Due today without a time is due all day, not overdue at one minute past midnight.
        #expect(reminder("a", days: 0).dueState(at: now, calendar: calendar) == .today)
        #expect(reminder("a", days: -1).dueState(at: now, calendar: calendar) == .overdue)
        #expect(reminder("a", days: 1).dueState(at: now, calendar: calendar) == .upcoming)
        #expect(reminder("a", days: 30).dueState(at: now, calendar: calendar) == .upcoming)
    }

    @Test func noDueDateIsUnscheduled() {
        #expect(reminder("a").dueState(at: now, calendar: calendar) == .unscheduled)
    }
}

@Suite("Reminder list selection")
struct ReminderListSelectionTests {
    private let lists = [groceries, work]

    @Test func emptyMeansEveryList() {
        #expect(ReminderAgenda.selectedList(id: "", in: lists) == nil)
    }

    @Test func findsTheChosenList() {
        #expect(ReminderAgenda.selectedList(id: "work", in: lists) == work)
    }

    @Test func aMissingListFallsBackToEveryList() {
        #expect(ReminderAgenda.selectedList(id: "from-another-mac", in: lists) == nil)
        #expect(ReminderAgenda.selectedList(id: "work", in: []) == nil)
    }

    @Test func filtersByList() {
        let items = [reminder("Milk"), reminder("Report", in: work), reminder("Eggs")]
        #expect(ReminderAgenda.items(items, in: work).map(\.title) == ["Report"])
        #expect(ReminderAgenda.items(items, in: groceries).map(\.title) == ["Milk", "Eggs"])
        #expect(ReminderAgenda.items(items, in: nil) == items)
    }

    @Test func scopeTodayKeepsOverdueAndTodayOnly() {
        let items = [
            reminder("Yesterday", days: -1),
            reminder("Earlier today", days: 0, hour: 8),
            reminder("Later today", days: 0, hour: 18),
            reminder("Tomorrow", days: 1),
            reminder("Someday"),
        ]
        #expect(
            ReminderAgenda.items(items, in: .today, at: now, calendar: calendar).map(\.title) == [
                "Yesterday", "Earlier today", "Later today",
            ])
        #expect(ReminderAgenda.items(items, in: .all, at: now, calendar: calendar) == items)
    }
}

@Suite("Reminder sorting")
struct ReminderSortingTests {
    @Test func dueDatesComeFirstSoonestFirst() {
        let items = [
            reminder("Someday"),
            reminder("Next week", days: 7),
            reminder("Tonight", days: 0, hour: 20),
            reminder("Overdue", days: -2, hour: 9),
            reminder("This morning", days: 0, hour: 8),
        ]
        #expect(
            ReminderAgenda.sorted(items).map(\.title) == [
                "Overdue", "This morning", "Tonight", "Next week", "Someday",
            ])
    }

    @Test func tiesGoToPriorityThenTitle() {
        let items = [
            reminder("item 10", days: 1),
            reminder("item 2", days: 1),
            reminder("Urgent", days: 1, priority: .high),
            reminder("Soonish", days: 1, priority: .low),
            reminder("Medium", days: 1, priority: .medium),
        ]
        #expect(
            ReminderAgenda.sorted(items).map(\.title) == [
                "Urgent", "Medium", "Soonish", "item 2", "item 10",
            ])
    }

    @Test func undatedRemindersSortByPriorityThenTitle() {
        let items = [
            reminder("b"),
            reminder("a"),
            reminder("Important", priority: .high),
        ]
        #expect(ReminderAgenda.sorted(items).map(\.title) == ["Important", "a", "b"])
    }

    @Test func sortIsStableAcrossIdenticalTitles() {
        let items = [reminder("Same", id: "2"), reminder("Same", id: "1")]
        #expect(ReminderAgenda.sorted(items).map(\.id) == ["1", "2"])
    }
}

@Suite("Reminder grouping")
struct ReminderGroupingTests {
    @Test func groupsInPopoverOrderAndSkipsEmptyGroups() {
        let items = [
            reminder("Someday"),
            reminder("Tomorrow", days: 1),
            reminder("Tonight", days: 0, hour: 20),
            reminder("Last week", days: -7),
            reminder("This morning", days: 0, hour: 8),
        ]
        let sections = ReminderAgenda.sections(items, at: now, calendar: calendar)
        #expect(sections.map(\.state) == [.overdue, .today, .upcoming, .unscheduled])
        #expect(sections.map(\.title) == ["Overdue", "Today", "Upcoming", "No Date"])
        #expect(
            sections.map { $0.items.map(\.title) } == [
                ["Last week", "This morning"], ["Tonight"], ["Tomorrow"], ["Someday"],
            ])

        let onlyToday = ReminderAgenda.sections([reminder("Today", days: 0)], at: now, calendar: calendar)
        #expect(onlyToday.map(\.state) == [.today])
        #expect(ReminderAgenda.sections([], at: now, calendar: calendar).isEmpty)
    }

    @Test func eachGroupIsSorted() {
        let items = [reminder("Later", days: 3), reminder("Sooner", days: 2)]
        let sections = ReminderAgenda.sections(items, at: now, calendar: calendar)
        #expect(sections.first?.items.map(\.title) == ["Sooner", "Later"])
    }
}

@Suite("Reminder due descriptions")
struct ReminderDueDescriptionTests {
    /// ICU puts a narrow no-break space before AM/PM; the tests don't care which space it is.
    private func describe(_ item: ReminderItem) -> String? {
        ReminderAgenda.dueDescription(for: item, at: now, calendar: calendar, locale: locale)?
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    @Test func namesNearbyDays() {
        #expect(describe(reminder("a", days: 0)) == "Today")
        #expect(describe(reminder("a", days: -1)) == "Yesterday")
        #expect(describe(reminder("a", days: 1)) == "Tomorrow")
    }

    @Test func usesTheWeekdayWithinTheWeek() {
        #expect(describe(reminder("a", days: 2)) == "Sunday")
        #expect(describe(reminder("a", days: 6)) == "Thursday")
    }

    @Test func usesADateFurtherOut() {
        #expect(describe(reminder("a", days: 7)) == "Oct 16")
        #expect(describe(reminder("a", days: -7)) == "Oct 2")
        #expect(describe(reminder("a", days: 90)) == "Jan 7, 2027")
    }

    @Test func appendsTheTimeWhenThereIsOne() {
        #expect(describe(reminder("a", days: 0, hour: 17)) == "Today, 5:00 PM")
        #expect(describe(reminder("a", days: -1, hour: 9)) == "Yesterday, 9:00 AM")
        #expect(describe(reminder("a", days: 7, hour: 13)) == "Oct 16, 1:00 PM")
    }

    @Test func nothingWithoutADueDate() {
        #expect(describe(reminder("a")) == nil)
    }
}
