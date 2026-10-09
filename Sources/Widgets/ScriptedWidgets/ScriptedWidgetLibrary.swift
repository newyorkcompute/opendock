import DockCore
import Foundation
import ScriptedWidgetRuntime
import SystemServices
import os

/// The scripted widgets installed on this Mac: every package in the Widgets folder, the
/// folders there that didn't load, and the last error each package's tiles reported. Watches
/// the folder and each package in it, so saving `main.js` reloads the tiles that run it.
///
/// Use ``shared`` in the app; tests build one on a temporary folder.
@Observable
public final class ScriptedWidgetLibrary {
    public static let shared = ScriptedWidgetLibrary(directory: ScriptedWidgetPackage.defaultDirectory())

    /// How long to wait after a file change before rescanning, so a save that writes several
    /// files reloads once.
    static let reloadDelay: Duration = .milliseconds(300)

    public let directory: URL
    public private(set) var packages: [ScriptedWidgetPackage] = []
    public private(set) var problems: [ScriptedWidgetPackage.Problem] = []
    public private(set) var hasLoaded = false
    /// The last error a tile running each package hit, by package id, for Settings.
    public private(set) var errors: [String: ScriptedWidgetError] = [:]

    @ObservationIgnored private var watchers: [FolderWatcher] = []
    @ObservationIgnored private var pendingReload: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.newyorkcompute.opendock", category: "Scripted")

    public init(directory: URL) {
        self.directory = directory
    }

    public func package(for id: String) -> ScriptedWidgetPackage? {
        packages.first { $0.id == id }
    }

    /// Scans the folder the first time something asks.
    public func loadIfNeeded() {
        guard !hasLoaded else { return }
        reload()
    }

    /// Rescans the Widgets folder now.
    public func reload() {
        let result = ScriptedWidgetPackage.scan(directory)
        packages = result.packages
        problems = result.problems
        hasLoaded = true
        errors = errors.filter { id, _ in result.packages.contains { $0.id == id } }
        for problem in result.problems {
            log.error("\(problem.folderName, privacy: .public): \(problem.message, privacy: .public)")
        }
        watch()
    }

    /// Records what a tile running `packageID` hit, or that it's fine again.
    func report(_ error: ScriptedWidgetError?, for packageID: String) {
        guard errors[packageID] != error else { return }
        errors[packageID] = error
        if let error {
            log.error("\(packageID, privacy: .public): \(error.description, privacy: .public)")
        }
    }

    /// Opens the Widgets folder in Finder, creating it first so there's something to open.
    public func revealInFinder() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        AppLauncher.revealInFinder(directory)
    }

    /// Watches the folder and every package in it. Most editors save by writing a new file
    /// and renaming it over the old one, which a directory watcher sees.
    private func watch() {
        watchers = ([directory] + packages.map(\.directory)).compactMap { url in
            FolderWatcher(url: url) { [weak self] in self?.scheduleReload() }
        }
    }

    private func scheduleReload() {
        pendingReload?.cancel()
        pendingReload = Task { [weak self] in
            try? await Task.sleep(for: Self.reloadDelay)
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }
}
