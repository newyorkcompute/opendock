import Foundation

/// One list in Reminders (an EventKit reminders calendar), as a plain value.
public struct ReminderList: Sendable, Hashable, Identifiable {
    /// The list's `calendarIdentifier`, which is what a tile stores to pick a list.
    public let id: String
    public let title: String
    /// The list's color as `#RRGGBB` (sRGB).
    public let colorHex: String

    public init(id: String, title: String, colorHex: String) {
        self.id = id
        self.title = title
        self.colorHex = colorHex
    }
}

/// One incomplete reminder, as a plain value the dock can render.
public struct ReminderItem: Sendable, Hashable, Identifiable {
    /// How urgent the reminder is, from EventKit's 0–9 scale.
    public enum Priority: Int, Sendable, Hashable, Comparable, CaseIterable {
        case high
        case medium
        case low
        case none

        /// EventKit priorities: 0 is none, 1–4 high, 5 medium, 6–9 low.
        public init(eventKitPriority: Int) {
            switch eventKitPriority {
            case 1 ... 4: self = .high
            case 5: self = .medium
            case 6 ... 9: self = .low
            default: self = .none
            }
        }

        public static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// The reminder's `calendarItemIdentifier`.
    public let id: String
    public let title: String
    public let listID: String
    public let listTitle: String
    /// The owning list's color as `#RRGGBB` (sRGB).
    public let listColorHex: String
    /// When the reminder is due, or nil for one without a date.
    public let dueDate: Date?
    /// True when the due date has a time of day. A reminder due "today" without a time is
    /// due all day, like an all-day event.
    public let dueDateHasTime: Bool
    public let priority: Priority
    public let notes: String?
    public let url: URL?

    public init(
        id: String,
        title: String,
        listID: String,
        listTitle: String,
        listColorHex: String,
        dueDate: Date? = nil,
        dueDateHasTime: Bool = false,
        priority: Priority = .none,
        notes: String? = nil,
        url: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.listID = listID
        self.listTitle = listTitle
        self.listColorHex = listColorHex
        self.dueDate = dueDate
        self.dueDateHasTime = dueDateHasTime
        self.priority = priority
        self.notes = notes
        self.url = url
    }

    /// Where the reminder stands relative to `now`.
    public func dueState(at now: Date, calendar: Calendar = .current) -> ReminderDueState {
        guard let dueDate else { return .unscheduled }
        if dueDateHasTime {
            if dueDate < now { return .overdue }
        } else if calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: now) {
            return .overdue
        }
        return calendar.isDate(dueDate, inSameDayAs: now) ? .today : .upcoming
    }
}

/// How a reminder's due date relates to now. The cases are in the order the popover lists them.
public enum ReminderDueState: Int, Sendable, Hashable, Comparable, CaseIterable {
    case overdue
    case today
    case upcoming
    case unscheduled

    /// The section header in the popover.
    public var title: String {
        switch self {
        case .overdue: "Overdue"
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .unscheduled: "No Date"
        }
    }

    public static func < (lhs: ReminderDueState, rhs: ReminderDueState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The reminders in one due state, for the popover.
public struct ReminderSection: Sendable, Hashable, Identifiable {
    public let state: ReminderDueState
    public let items: [ReminderItem]

    public var id: ReminderDueState { state }
    public var title: String { state.title }

    public init(state: ReminderDueState, items: [ReminderItem]) {
        self.state = state
        self.items = items
    }
}
