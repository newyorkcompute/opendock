import Foundation

/// Which reminders a tile counts and its popover lists.
public enum ReminderScope: String, Sendable, Hashable, CaseIterable {
    /// Every incomplete reminder.
    case all
    /// Only reminders due today or overdue, like the Reminders app's badge.
    case today
}

/// Picks, orders, and groups reminders for a tile. Pure functions over `ReminderItem`
/// values, so the widget's logic is testable without EventKit.
public enum ReminderAgenda {
    /// The list a tile is set to, or nil for every list: when `listID` is empty, or names a
    /// list that no longer exists (or never did on this Mac, for an imported layout).
    public static func selectedList(id listID: String, in lists: [ReminderList]) -> ReminderList? {
        guard !listID.isEmpty else { return nil }
        return lists.first { $0.id == listID }
    }

    /// `items` from `list`, or all of them when `list` is nil.
    public static func items(_ items: [ReminderItem], in list: ReminderList?) -> [ReminderItem] {
        guard let list else { return items }
        return items.filter { $0.listID == list.id }
    }

    /// `items` that fall within `scope` at `now`.
    public static func items(
        _ items: [ReminderItem], in scope: ReminderScope, at now: Date, calendar: Calendar = .current
    ) -> [ReminderItem] {
        switch scope {
        case .all:
            return items
        case .today:
            return items.filter { $0.dueState(at: now, calendar: calendar) <= .today }
        }
    }

    /// Reminders with a due date first, soonest first; then the rest. Ties go to the higher
    /// priority, then the title.
    public static func sorted(_ items: [ReminderItem]) -> [ReminderItem] {
        items.sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case let (lhsDue?, rhsDue?) where lhsDue != rhsDue:
                return lhsDue < rhsDue
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                break
            }
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            let titles = lhs.title.localizedStandardCompare(rhs.title)
            if titles != .orderedSame { return titles == .orderedAscending }
            return lhs.id < rhs.id
        }
    }

    /// `items` grouped by due state in the order the popover shows them (overdue, today,
    /// upcoming, no date), each group sorted. Empty groups are left out.
    public static func sections(
        _ items: [ReminderItem], at now: Date, calendar: Calendar = .current
    ) -> [ReminderSection] {
        let grouped = Dictionary(grouping: items) { $0.dueState(at: now, calendar: calendar) }
        return ReminderDueState.allCases.compactMap { state in
            guard let group = grouped[state], !group.isEmpty else { return nil }
            return ReminderSection(state: state, items: sorted(group))
        }
    }

    /// A short description of when `item` is due, for a row in the popover: "Today",
    /// "Today, 5:00 PM", "Yesterday", "Tomorrow", a weekday within the week, or a date.
    public static func dueDescription(
        for item: ReminderItem, at now: Date, calendar: Calendar = .current, locale: Locale = .current
    ) -> String? {
        guard let dueDate = item.dueDate else { return nil }
        var calendar = calendar
        calendar.locale = locale
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)

        let day: String
        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: dueDate)
        let days = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
        switch days {
        case 0:
            day = "Today"
        case -1:
            day = "Yesterday"
        case 1:
            day = "Tomorrow"
        case 2 ... 6:
            day = dueDate.formatted(style.weekday(.wide))
        default:
            var dateStyle = style.month(.abbreviated).day()
            if calendar.component(.year, from: dueDate) != calendar.component(.year, from: now) {
                dateStyle = dateStyle.year()
            }
            day = dueDate.formatted(dateStyle)
        }

        guard item.dueDateHasTime else { return day }
        return "\(day), \(dueDate.formatted(style.hour().minute()))"
    }
}
