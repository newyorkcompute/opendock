import AppKit
import CoreServices
import DockCore
import Observation
import os

/// Whether OpenDock may send Apple Events to Finder (Privacy & Security > Automation),
/// which is how it asks what's in the Trash and has the Trash emptied.
@MainActor
public protocol FinderAutomationPermission {
    func status() -> FinderAutomationStatus
    /// Opens Privacy & Security > Automation in System Settings, for after the user has
    /// said no: macOS asks only once.
    func openSystemSettings()
}

public enum FinderAutomationStatus: Sendable {
    case granted
    case denied
    /// The user hasn't been asked yet; macOS asks the first time an event is sent.
    case notDetermined
    /// The question couldn't be answered, as when Finder isn't running.
    case unknown
}

/// The real permission, through `AEDeterminePermissionToAutomateTarget`.
@MainActor
public struct SystemFinderAutomationPermission: FinderAutomationPermission {
    public init() {}

    public func status() -> FinderAutomationStatus {
        let finder = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        guard let target = finder.aeDesc else { return .unknown }
        let wildcard: FourCharCode = 0x2A2A_2A2A // '****', any event
        switch AEDeterminePermissionToAutomateTarget(target, wildcard, wildcard, false) {
        case 0: return .granted // noErr
        case -1743: return .denied // errAEEventNotPermitted
        case -1744: return .notDetermined // errAEEventWouldRequireUserConsent
        default: return .unknown
        }
    }

    public func openSystemSettings() {
        SystemSettingsPane.automation.open()
    }
}

/// Whether the Trash has anything in it, kept up to date while the dock shows a Trash item,
/// and what the item does: open the Trash in Finder, and have Finder empty it.
///
/// `~/.Trash` can be listed only with Full Disk Access, which OpenDock doesn't ask for. So
/// the Trash is read directly when that works, and Finder is asked otherwise, with the
/// one-time "OpenDock wants access to control Finder" prompt. Changes are noticed by
/// watching the folder, or by polling its modification date when it can't be watched.
@MainActor
@Observable
public final class TrashMonitor {
    /// Lists the names of the items in the Trash at a URL, or throws when macOS won't let
    /// OpenDock look.
    public typealias Reader = @MainActor (URL) throws -> [String]

    /// Whether the Trash is empty, as far as is known: the icon to show. True until the
    /// first successful look.
    public private(set) var isEmpty = true
    /// False while neither reading the Trash nor asking Finder has worked, so `isEmpty` is
    /// only a guess.
    public private(set) var isKnown = false
    /// True when the user has refused OpenDock control of Finder, which is then the only
    /// thing in the way of knowing whether the Trash is empty, and of emptying it.
    public private(set) var finderAccessDenied = false
    /// Whether Finder may be asked (and the user prompted) when the Trash can't be read.
    /// Off until the welcome window has been seen, so a fresh install isn't greeted by a
    /// permission prompt. See `setMayAskFinder`.
    public private(set) var mayAskFinder = false
    /// How often the Trash is checked for changes when it can't be watched.
    public static let pollInterval = Duration.seconds(2)
    /// Several file system events arrive for one change; one look covers them.
    public static let refreshDelay = Duration.milliseconds(200)

    public let url: URL

    @ObservationIgnored private let reader: Reader
    @ObservationIgnored private let scripts: any AppleScriptRunner
    @ObservationIgnored private let automation: any FinderAutomationPermission
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var finderTask: Task<Void, Never>?
    @ObservationIgnored private var isWatching = false
    @ObservationIgnored private let log = Logger(subsystem: "com.newyorkcompute.opendock", category: "Trash")

    /// - Parameters:
    ///   - url: The Trash folder; the user's `~/.Trash` by default.
    ///   - reader: Lists the folder; the default uses `FileManager`.
    ///   - scripts: Runs the AppleScript that asks Finder; the default uses `osascript`.
    ///   - automation: Tells whether Finder may be scripted.
    public init(
        url: URL? = nil,
        reader: @escaping Reader = { try FileManager.default.contentsOfDirectory(atPath: $0.path) },
        scripts: any AppleScriptRunner = OSAScriptRunner(),
        automation: any FinderAutomationPermission = SystemFinderAutomationPermission()
    ) {
        self.url =
            url ?? FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
        self.reader = reader
        self.scripts = scripts
        self.automation = automation
    }

    // MARK: - Watching

    /// Allows (or stops) asking Finder. Allowing it asks straight away if the Trash is still
    /// unaccounted for.
    public func setMayAskFinder(_ allowed: Bool) {
        guard allowed != mayAskFinder else { return }
        mayAskFinder = allowed
        if allowed, isWatching, !isKnown { refresh() }
    }

    /// Starts keeping `isEmpty` up to date. Called when a Trash item appears in the dock.
    public func start() {
        guard !isWatching else { return }
        isWatching = true
        watcher = FolderWatcher(url: url) { [weak self] in self?.scheduleRefresh() }
        if watcher == nil {
            poll()
        }
        refresh()
    }

    public func stop() {
        guard isWatching else { return }
        isWatching = false
        watcher?.stop()
        watcher = nil
        pollTask?.cancel()
        pollTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        finderTask?.cancel()
        finderTask = nil
    }

    /// Looks again when the folder's modification date changes, which it does whenever
    /// something is put in the Trash or taken out, even when its contents can't be seen.
    private func poll() {
        pollTask = Task { [weak self] in
            var seen = self?.modificationDate
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard let self, !Task.isCancelled else { return }
                let date = modificationDate
                guard date != seen else { continue }
                seen = date
                refresh()
            }
        }
    }

    private var modificationDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: Self.refreshDelay)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    /// Finds out whether the Trash is empty: from the folder itself when it can be read,
    /// else from Finder (asynchronously, through `osascript`).
    public func refresh() {
        if let names = try? reader(url) {
            finderTask?.cancel()
            finderTask = nil
            update(isEmpty: TrashContents.isEmpty(itemNames: names))
            return
        }
        askFinder()
    }

    private func askFinder() {
        guard mayAskFinder else { return }
        switch automation.status() {
        case .denied:
            finderAccessDenied = true
            isKnown = false
            return
        case .granted, .notDetermined, .unknown:
            break
        }
        guard finderTask == nil else { return }
        finderTask = Task { [weak self, scripts] in
            let reply = await scripts.run(TrashContents.countScript)
            guard let self, !Task.isCancelled else { return }
            finderTask = nil
            if let count = TrashContents.itemCount(inFinderReply: reply) {
                update(isEmpty: count == 0)
            } else {
                isKnown = false
                // The usual reason: the user just said no to the prompt.
                finderAccessDenied = automation.status() == .denied
                log.debug("Finder didn't say how many items are in the Trash")
            }
        }
    }

    private func update(isEmpty: Bool) {
        if self.isEmpty != isEmpty { self.isEmpty = isEmpty }
        if !isKnown { isKnown = true }
        if finderAccessDenied { finderAccessDenied = false }
    }

    /// Waits for an answer from Finder that's on its way, if one is. For tests.
    public func finishAskingFinder() async {
        await finderTask?.value
    }

    // MARK: - Actions

    /// Shows the Trash in Finder, as clicking it in Apple's Dock does.
    public func open() {
        AppLauncher.open(url: url)
    }

    /// Has Finder empty the Trash, with its usual confirmation. If the user has refused
    /// OpenDock control of Finder, opens the System Settings pane where that's changed.
    public func empty() {
        if automation.status() == .denied {
            finderAccessDenied = true
            automation.openSystemSettings()
            return
        }
        Task { [scripts] in
            _ = await scripts.run(TrashContents.emptyScript)
        }
    }

    public func openAutomationSettings() {
        automation.openSystemSettings()
    }

    isolated deinit {
        stop()
    }
}
