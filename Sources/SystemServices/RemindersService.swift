import DockCore
import EventKit
import Foundation
import Observation
import os

/// Wraps `EKEventStore` for reminders and publishes the lists and every incomplete reminder.
///
/// Mirrors ``CalendarService``: it never prompts on its own except through
/// ``requestAccessIfNeeded()`` (called when a tile appears, once widgets may request access)
/// and ``requestAccess()``. It refreshes on `EKEventStoreChanged` and whenever ``refresh(force:)``
/// is called — the tiles call it once a minute while the dock is visible. Use ``shared`` so all
/// tiles share one store. Reminders and events have separate permissions, so this has its own
/// store rather than sharing `CalendarService`'s.
@MainActor
@Observable
public final class RemindersService {
    /// Process-wide instance shared by all reminders tiles.
    public static let shared = RemindersService()

    /// Current EventKit authorization for reminders.
    public private(set) var authorizationStatus: EKAuthorizationStatus
    /// Every list, by title.
    public private(set) var lists: [ReminderList] = []
    /// Every incomplete reminder in every list, unsorted. Pick and order them with `ReminderAgenda`.
    public private(set) var reminders: [ReminderItem] = []
    /// Time of the last refresh, so views depending on "now" are invalidated.
    public private(set) var lastRefresh = Date()

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private let log = Logger(subsystem: "com.newyorkcompute.opendock", category: "Reminders")
    @ObservationIgnored private var changeObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var hasPrompted = false
    @ObservationIgnored private var lastRefreshTime: ContinuousClock.Instant?
    /// Bumped per fetch so a slow one can't overwrite a newer result.
    @ObservationIgnored private var fetchGeneration = 0

    public init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        refresh(force: true)
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(force: true) }
        }
    }

    isolated deinit {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
    }

    // MARK: Authorization

    /// True when full access to reminders has been granted.
    public var hasAccess: Bool { authorizationStatus == .fullAccess }
    /// True when the user (or a profile) has explicitly refused access.
    public var isDenied: Bool { authorizationStatus == .denied || authorizationStatus == .restricted }
    /// True when the system hasn't asked the user yet.
    public var isUndetermined: Bool { authorizationStatus == .notDetermined }

    /// Asks the system for full reminders access and refreshes on completion.
    public func requestAccess() async {
        hasPrompted = true
        _ = try? await store.requestFullAccessToReminders()
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        refresh(force: true)
    }

    /// Requests access at most once per launch, and only if the user hasn't decided yet.
    public func requestAccessIfNeeded() async {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        guard authorizationStatus == .notDetermined, !hasPrompted else { return }
        await requestAccess()
    }

    // MARK: Reminders

    /// Re-reads the lists and starts fetching incomplete reminders; `reminders` updates when the
    /// fetch completes. Unless `force` is set, calls within 5 seconds of the last one are ignored,
    /// so several tiles can drive refreshes without duplicating work.
    public func refresh(force: Bool = false) {
        let clock = ContinuousClock()
        if !force, let last = lastRefreshTime, clock.now - last < .seconds(5) { return }
        lastRefreshTime = clock.now

        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        lastRefresh = Date()
        guard hasAccess else {
            if !lists.isEmpty { lists = [] }
            if !reminders.isEmpty { reminders = [] }
            return
        }

        let newLists = store.calendars(for: .reminder)
            .map(Self.list(for:))
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        if newLists != lists { lists = newLists }

        fetchGeneration += 1
        let generation = fetchGeneration
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil)
        _ = store.fetchReminders(matching: predicate) { [weak self] fetched in
            let items = (fetched ?? []).map(Self.item(for:))
            Task { @MainActor [weak self] in
                guard let self, generation == self.fetchGeneration else { return }
                if items != self.reminders { self.reminders = items }
            }
        }
    }

    /// Refreshes once a minute until the surrounding task is cancelled.
    /// Run it from a view's `.task(id:)` while the dock is visible.
    public func autoRefresh() async {
        while !Task.isCancelled {
            refresh()
            try? await Task.sleep(for: .seconds(60))
        }
    }

    /// Marks `item` completed in Reminders. The tile drops it right away; the store's change
    /// notification confirms it (or brings it back if the save failed).
    public func complete(_ item: ReminderItem) {
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else {
            log.error("Reminder \(item.id, privacy: .public) not found; it may have been completed elsewhere")
            reminders.removeAll { $0.id == item.id }
            return
        }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            reminders.removeAll { $0.id == item.id }
        } catch {
            log.error("Couldn't complete reminder: \(error.localizedDescription, privacy: .public)")
            refresh(force: true)
        }
    }

    // MARK: Mapping

    private nonisolated static func list(for calendar: EKCalendar) -> ReminderList {
        ReminderList(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            colorHex: EventKitColors.hex(for: calendar.cgColor))
    }

    private nonisolated static func item(for reminder: EKReminder) -> ReminderItem {
        let components = reminder.dueDateComponents
        let notes = reminder.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReminderItem(
            id: reminder.calendarItemIdentifier,
            title: (reminder.title?.isEmpty == false ? reminder.title : nil) ?? "Untitled",
            listID: reminder.calendar?.calendarIdentifier ?? "",
            listTitle: reminder.calendar?.title ?? "Reminders",
            listColorHex: EventKitColors.hex(for: reminder.calendar?.cgColor),
            dueDate: components.flatMap { $0.date ?? Calendar.current.date(from: $0) },
            dueDateHasTime: components?.hour != nil,
            priority: ReminderItem.Priority(eventKitPriority: reminder.priority),
            notes: notes?.isEmpty == false ? notes : nil,
            url: reminder.url)
    }
}
