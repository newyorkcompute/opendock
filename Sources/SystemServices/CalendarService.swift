import AppKit
import EventKit
import Foundation
import Observation

/// A Sendable snapshot of one calendar event occurrence.
public struct EventSummary: Sendable, Hashable, Identifiable {
    /// Unique per occurrence (recurring events share an `eventIdentifier`).
    public let id: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool
    /// The owning calendar's color as `#RRGGBB` (sRGB).
    public let calendarColorHex: String
    public let location: String?
    /// A Zoom / Google Meet / Teams / Webex link found in the event's URL, location or notes.
    public let conferenceURL: URL?

    public init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendarColorHex: String,
        location: String?,
        conferenceURL: URL?
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.calendarColorHex = calendarColorHex
        self.location = location
        self.conferenceURL = conferenceURL
    }

    /// True while `date` falls within the event.
    public func isInProgress(at date: Date) -> Bool {
        startDate <= date && date < endDate
    }
}

/// Wraps `EKEventStore` and publishes today's events.
///
/// The service never prompts on its own except through ``requestAccessIfNeeded()``
/// (called when a tile appears, once widgets may request access) and ``requestAccess()``. It refreshes on
/// `EKEventStoreChanged` and whenever ``refresh(force:)`` is called — the tiles call it
/// once a minute while the dock is visible. Use ``shared`` so all tiles share one store.
@MainActor
@Observable
public final class CalendarService {
    /// Process-wide instance shared by all calendar tiles.
    public static let shared = CalendarService()

    /// Current EventKit authorization for events.
    public private(set) var authorizationStatus: EKAuthorizationStatus
    /// Today's events: all-day first, then by start time.
    public private(set) var todayEvents: [EventSummary] = []
    /// Time of the last refresh, so views depending on "now" are invalidated.
    public private(set) var lastRefresh = Date()

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var changeObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var hasPrompted = false
    @ObservationIgnored private var lastRefreshTime: ContinuousClock.Instant?

    public init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
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

    /// True when full read access to events has been granted.
    public var hasAccess: Bool { authorizationStatus == .fullAccess }
    /// True when the user (or a profile) has explicitly refused access.
    public var isDenied: Bool { authorizationStatus == .denied || authorizationStatus == .restricted }
    /// True when the system hasn't asked the user yet.
    public var isUndetermined: Bool { authorizationStatus == .notDetermined }

    /// Asks the system for full calendar access and refreshes on completion.
    public func requestAccess() async {
        hasPrompted = true
        _ = try? await store.requestFullAccessToEvents()
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        refresh(force: true)
    }

    /// Requests access at most once per launch, and only if the user hasn't decided yet.
    public func requestAccessIfNeeded() async {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        guard authorizationStatus == .notDetermined, !hasPrompted else { return }
        await requestAccess()
    }

    // MARK: Events

    /// The next non-all-day event that is in progress or starts later today.
    public var nextEvent: EventSummary? { nextEvent(at: Date()) }

    /// The next non-all-day event that is in progress at, or starts after, `date`.
    public func nextEvent(at date: Date) -> EventSummary? {
        todayEvents.first { !$0.isAllDay && $0.endDate > date }
    }

    /// Re-reads today's events. Unless `force` is set, calls within 5 seconds of the last one are ignored,
    /// so several tiles can drive refreshes without duplicating work.
    public func refresh(force: Bool = false) {
        let clock = ContinuousClock()
        if !force, let last = lastRefreshTime, clock.now - last < .seconds(5) { return }
        lastRefreshTime = clock.now

        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        lastRefresh = Date()
        guard hasAccess else {
            if !todayEvents.isEmpty { todayEvents = [] }
            return
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: lastRefresh)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .map(Self.summary(for:))
            .sorted {
                if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
                return ($0.startDate, $0.title) < ($1.startDate, $1.title)
            }
        if events != todayEvents { todayEvents = events }
    }

    /// Refreshes once a minute until the surrounding task is cancelled.
    /// Run it from a view's `.task(id:)` while the dock is visible.
    public func autoRefresh() async {
        while !Task.isCancelled {
            refresh()
            try? await Task.sleep(for: .seconds(60))
        }
    }

    // MARK: Mapping

    private static func summary(for event: EKEvent) -> EventSummary {
        let start = event.startDate ?? Date()
        let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        return EventSummary(
            id: "\(event.eventIdentifier ?? UUID().uuidString)-\(Int(start.timeIntervalSince1970))",
            title: (event.title?.isEmpty == false ? event.title : nil) ?? "Untitled",
            startDate: start,
            endDate: event.endDate ?? start,
            isAllDay: event.isAllDay,
            calendarColorHex: EventKitColors.hex(for: event.calendar?.cgColor),
            location: location?.isEmpty == false ? location : nil,
            conferenceURL: conferenceURL(url: event.url, location: location, notes: event.notes)
        )
    }

    private static let conferenceHosts = [
        "zoom.us", "zoomgov.com", "meet.google.com", "teams.microsoft.com",
        "teams.live.com", "webex.com", "whereby.com", "gotomeeting.com",
    ]

    /// Finds the first video-call link among the event's URL, location and notes.
    static func conferenceURL(url: URL?, location: String?, notes: String?) -> URL? {
        func isConference(_ url: URL) -> Bool {
            guard let host = url.host()?.lowercased() else { return false }
            return conferenceHosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }

        if let url, isConference(url) { return url }

        let text = [location, notes].compactMap { $0 }.joined(separator: "\n")
        guard !text.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).lazy.compactMap(\.url).first(where: isConference)
    }
}
