import Foundation
import Observation
import os

/// A Focus mode as set up in System Settings > Focus.
public struct FocusMode: Hashable, Identifiable, Sendable {
    /// The system's identifier, such as `com.apple.focus.work`. It survives renaming the Focus.
    public var id: String
    public var name: String
    /// The SF Symbol System Settings shows for the Focus, if the configuration names one.
    public var symbolName: String?

    public init(id: String, name: String, symbolName: String? = nil) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
    }

    public static let doNotDisturbID = "com.apple.donotdisturb.mode.default"
}

/// The Focus modes on this Mac and which one is on.
public struct FocusSnapshot: Hashable, Sendable {
    public var modes: [FocusMode]
    /// The identifier of the Focus that's on, or nil when none is.
    public var activeModeID: String?

    public init(modes: [FocusMode] = [], activeModeID: String? = nil) {
        self.modes = modes
        self.activeModeID = activeModeID
    }
}

/// Why the Focus state couldn't be read.
public enum FocusReadError: Error, Equatable, Sendable {
    /// macOS doesn't let OpenDock read the Focus database. Full Disk Access would.
    case accessDenied
    /// There's no Focus database, or it couldn't be understood.
    case unavailable
}

/// Where Focus state comes from. `DoNotDisturbDatabase` reads it from macOS; tests use a
/// stand-in.
@MainActor
public protocol FocusStateSource: AnyObject {
    /// The modes and the active one, now. Throws a `FocusReadError`.
    func readSnapshot() throws -> FocusSnapshot
    /// Runs `onChange` whenever the state may have changed, until `stopWatching()`. It may run
    /// several times for one change. Throws a `FocusReadError` when watching isn't possible.
    func startWatching(onChange: @escaping @MainActor () -> Void) throws
    func stopWatching()
    /// Opens the pane of System Settings where the user grants access.
    func openAccessSettings()
}

/// Keeps track of the Focus modes on this Mac and which one is on.
///
/// macOS has no public API that names the active Focus, so it's read from the Focus
/// database (`~/Library/DoNotDisturb/DB`), which needs Full Disk Access. Without access,
/// `access` says so and nothing is read again until `refresh()`.
@MainActor
@Observable
public final class FocusModeMonitor {
    public enum Access: Equatable, Sendable {
        /// Nothing has been read yet.
        case unknown
        case granted
        /// Full Disk Access is missing.
        case denied
        /// There's no Focus database to read.
        case unavailable
    }

    public private(set) var access = Access.unknown
    /// Do Not Disturb first, then the rest by name.
    public private(set) var modes: [FocusMode] = []
    /// The identifier of the Focus that's on, or nil when none is.
    public private(set) var activeModeID: String?

    public var activeMode: FocusMode? {
        guard let activeModeID else { return nil }
        return modes.first { $0.id == activeModeID } ?? FocusMode(id: activeModeID, name: activeModeID)
    }

    /// How long to wait after a change before reading, so one change is read once.
    static let changeDelay = Duration.milliseconds(150)
    /// How long to wait before reading again when a read fails mid-write.
    static let retryDelay = Duration.milliseconds(500)

    @ObservationIgnored private let source: any FocusStateSource
    @ObservationIgnored private var isWatching = false
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var hasRetried = false
    @ObservationIgnored private let log = Logger(subsystem: "com.newyorkcompute.opendock", category: "FocusModeMonitor")

    public init(source: any FocusStateSource) {
        self.source = source
    }

    isolated deinit {
        stop()
    }

    /// Reads the state now and keeps it up to date.
    public func start() {
        refresh()
    }

    public func stop() {
        readTask?.cancel()
        readTask = nil
        if isWatching {
            source.stopWatching()
            isWatching = false
        }
    }

    /// Reads the state again, for instance when the user may have just granted access.
    public func refresh() {
        readTask?.cancel()
        readTask = nil
        do {
            let snapshot = try source.readSnapshot()
            apply(snapshot)
            hasRetried = false
            watch()
        } catch FocusReadError.accessDenied {
            setAccess(.denied)
            stop()
        } catch {
            if isWatching, !hasRetried {
                // Probably caught the database mid-write. Try once more before giving up.
                hasRetried = true
                scheduleRead(after: Self.retryDelay)
            } else {
                setAccess(.unavailable)
            }
        }
    }

    public func openAccessSettings() {
        source.openAccessSettings()
    }

    private func apply(_ snapshot: FocusSnapshot) {
        setAccess(.granted)
        if modes != snapshot.modes { modes = snapshot.modes }
        if activeModeID != snapshot.activeModeID {
            activeModeID = snapshot.activeModeID
            log.info("Focus is now \(snapshot.activeModeID ?? "off", privacy: .public)")
        }
    }

    private func setAccess(_ new: Access) {
        guard access != new else { return }
        access = new
        if new != .granted {
            if !modes.isEmpty { modes = [] }
            if activeModeID != nil { activeModeID = nil }
        }
    }

    private func watch() {
        guard !isWatching else { return }
        do {
            try source.startWatching { [weak self] in self?.scheduleRead(after: Self.changeDelay) }
            isWatching = true
        } catch {
            log.error("Can't watch the Focus database; Focus changes won't be noticed until the next refresh")
        }
    }

    private func scheduleRead(after delay: Duration) {
        readTask?.cancel()
        readTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
