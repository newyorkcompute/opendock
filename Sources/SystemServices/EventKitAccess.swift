import EventKit
import Foundation
import Observation

/// What ``CalendarService`` and ``RemindersService`` have in common: one `EKEventStore`, its
/// authorization for one entity type, the prompt-at-most-once rule, the `EKEventStoreChanged`
/// observer, and the refresh throttle. Each service owns one (events and reminders have
/// separate TCC permissions, so they can't share a store) and supplies the fetch.
@MainActor
@Observable
public final class EventKitAccess {
    public let entityType: EKEntityType
    /// Current EventKit authorization for `entityType`.
    public private(set) var authorizationStatus: EKAuthorizationStatus
    /// Time of the last refresh the throttle let through, so views depending on "now" are invalidated.
    public private(set) var lastRefresh = Date()

    @ObservationIgnored let store = EKEventStore()
    /// Runs on the main actor when the store reports a change; the owning service refreshes.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    @ObservationIgnored private var changeObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var hasPrompted = false
    @ObservationIgnored private var throttle = RefreshThrottle()

    init(entityType: EKEntityType) {
        self.entityType = entityType
        authorizationStatus = EKEventStore.authorizationStatus(for: entityType)
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
    }

    isolated deinit {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
    }

    // MARK: Authorization

    /// True when full access has been granted.
    public var hasAccess: Bool { authorizationStatus == .fullAccess }
    /// True when the user (or a profile) has explicitly refused access.
    public var isDenied: Bool { authorizationStatus == .denied || authorizationStatus == .restricted }
    /// True when the system hasn't asked the user yet.
    public var isUndetermined: Bool { authorizationStatus == .notDetermined }

    /// Asks the system for full access, then tells the owner to refresh.
    public func requestAccess() async {
        hasPrompted = true
        switch entityType {
        case .reminder: _ = try? await store.requestFullAccessToReminders()
        default: _ = try? await store.requestFullAccessToEvents()
        }
        readAuthorizationStatus()
        onChange?()
    }

    /// Requests access at most once per launch, and only if the user hasn't decided yet.
    public func requestAccessIfNeeded() async {
        readAuthorizationStatus()
        guard authorizationStatus == .notDetermined, !hasPrompted else { return }
        await requestAccess()
    }

    private func readAuthorizationStatus() {
        let status = EKEventStore.authorizationStatus(for: entityType)
        if status != authorizationStatus { authorizationStatus = status }
    }

    // MARK: Refresh

    /// The start of a refresh: false when one ran less than five seconds ago and `force` is off,
    /// so several tiles can drive refreshes without duplicating work. Otherwise re-reads the
    /// authorization status, stamps `lastRefresh`, and returns true for the owner to fetch.
    func beginRefresh(force: Bool) -> Bool {
        guard throttle.admit(force: force, now: ContinuousClock.now) else { return false }
        readAuthorizationStatus()
        lastRefresh = Date()
        return true
    }
}

/// Lets a refresh through at most once per `interval` unless forced.
struct RefreshThrottle: Sendable {
    var interval: Duration = .seconds(5)
    private(set) var last: ContinuousClock.Instant?

    mutating func admit(force: Bool, now: ContinuousClock.Instant) -> Bool {
        if !force, let last, now - last < interval { return false }
        last = now
        return true
    }
}
