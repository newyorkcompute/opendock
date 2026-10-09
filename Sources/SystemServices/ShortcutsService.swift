import DockCore
import Foundation
import Observation
import os

/// What one invocation of the `shortcuts` tool produced.
public struct ShortcutsCommandResult: Hashable, Sendable {
    public var exitStatus: Int32
    public var standardOutput: String
    public var standardError: String
    /// True when the tool was stopped for running longer than the caller allowed.
    public var timedOut: Bool

    public init(exitStatus: Int32, standardOutput: String = "", standardError: String = "", timedOut: Bool = false) {
        self.exitStatus = exitStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.timedOut = timedOut
    }
}

/// Runs the `shortcuts` command-line tool. A protocol so ``ShortcutsService`` can be tested
/// without the tool or any shortcuts.
public protocol ShortcutsCommandRunner: Sendable {
    /// Whether the tool exists on this Mac.
    var isAvailable: Bool { get }
    /// Runs the tool with `arguments`, waiting at most `timeout` seconds, and returns what it
    /// did, or `nil` when it couldn't be started at all.
    func run(_ arguments: [String], timeout: TimeInterval) async -> ShortcutsCommandResult?
}

/// Runs `/usr/bin/shortcuts`, the tool macOS ships with the Shortcuts app, in a child process
/// off the main thread. Shortcuts started this way run in the background: the Shortcuts app
/// doesn't come to the front, though a shortcut's own dialogs still appear.
public struct ShortcutsCommandLine: ShortcutsCommandRunner {
    public static let toolURL = URL(fileURLWithPath: "/usr/bin/shortcuts")

    public init() {}

    public var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: Self.toolURL.path) }

    public func run(_ arguments: [String], timeout: TimeInterval) async -> ShortcutsCommandResult? {
        await withCheckedContinuation { continuation in
            Self.execute(arguments: arguments, timeout: timeout) { continuation.resume(returning: $0) }
        }
    }

    /// Runs the tool on a background queue and calls `completion` once, with `nil` when it
    /// couldn't be launched.
    private static func execute(
        arguments: [String], timeout: TimeInterval, completion: @escaping @Sendable (ShortcutsCommandResult?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = toolURL
            process.arguments = arguments
            let output = Pipe()
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            // Errors go to a file rather than a second pipe, so there's nothing to drain
            // concurrently while standard output is read to its end.
            let errorURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("opendock-shortcuts-\(UUID().uuidString).log")
            defer { try? FileManager.default.removeItem(at: errorURL) }
            let errorHandle =
                FileManager.default.createFile(atPath: errorURL.path, contents: nil)
                ? try? FileHandle(forWritingTo: errorURL) : nil
            process.standardError = errorHandle ?? FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                completion(nil)
                return
            }

            // A shortcut waiting on a dialog nobody answers would hold this thread forever.
            let pid = process.processIdentifier
            let timedOut = OSAllocatedUnfairLock(initialState: false)
            let watchdog = DispatchWorkItem {
                timedOut.withLock { $0 = true }
                kill(pid, SIGTERM)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

            let outputData = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            watchdog.cancel()
            try? errorHandle?.close()
            let errorData = (try? Data(contentsOf: errorURL)) ?? Data()

            completion(
                ShortcutsCommandResult(
                    exitStatus: process.terminationReason == .exit ? process.terminationStatus : -1,
                    standardOutput: String(decoding: outputData, as: UTF8.self),
                    standardError: String(decoding: errorData, as: UTF8.self),
                    timedOut: timedOut.withLock { $0 }))
        }
    }
}

/// Lists the shortcuts on this Mac and runs them, keeping each one's latest ``ShortcutRunState``
/// so every tile and popover shows the same thing.
///
/// Nothing runs on its own: tiles call ``refresh(force:)`` when they appear and when the
/// popover opens, and ``run(_:)`` when clicked. Use ``shared`` so the list is read once.
@MainActor
@Observable
public final class ShortcutsService {
    /// Process-wide instance shared by all Shortcuts tiles.
    public static let shared = ShortcutsService()

    /// How long a `shortcuts list` may take before it's given up on.
    public nonisolated static let listTimeout: TimeInterval = 15
    /// How long a shortcut may run before it's stopped. Shortcuts can legitimately wait on
    /// their own dialogs, so this is generous.
    public nonisolated static let runTimeout: TimeInterval = 600
    /// Unless forced, refreshes closer together than this are skipped.
    public nonisolated static let refreshInterval: Duration = .seconds(30)

    /// Every shortcut's name, in the Shortcuts app's order. Empty until the first refresh finishes.
    public private(set) var shortcuts: [String] = []
    /// False until `shortcuts list` has answered once, so an empty list isn't mistaken for "none yet".
    public private(set) var hasLoaded = false
    /// True while `shortcuts list` is running.
    public private(set) var isRefreshing = false
    /// Whether the `shortcuts` tool exists. Without it nothing here works.
    public private(set) var isAvailable: Bool
    /// The latest run of each shortcut, by name.
    public private(set) var runs: [String: ShortcutRunState] = [:]

    @ObservationIgnored private let runner: any ShortcutsCommandRunner
    @ObservationIgnored private let log = Logger(subsystem: "com.newyorkcompute.opendock", category: "Shortcuts")
    @ObservationIgnored private var lastRefresh: ContinuousClock.Instant?
    @ObservationIgnored private var refreshInFlight: Task<Void, Never>?

    public init(runner: any ShortcutsCommandRunner = ShortcutsCommandLine()) {
        self.runner = runner
        isAvailable = runner.isAvailable
    }

    /// Whether a shortcut with this name exists, as of the last refresh. `nil` before the first one.
    public func exists(_ name: String) -> Bool? {
        hasLoaded ? shortcuts.contains(name) : nil
    }

    /// The latest run of `name`, if it has run since launch.
    public func state(of name: String) -> ShortcutRunState? {
        runs[name]
    }

    // MARK: Listing

    /// Re-reads the list of shortcuts. Unless `force` is set, a call within ``refreshInterval``
    /// of the last one does nothing, so several tiles can ask freely. Concurrent calls share one read.
    public func refresh(force: Bool = false) async {
        if let refreshInFlight {
            await refreshInFlight.value
            return
        }
        if !force, let lastRefresh, ContinuousClock().now - lastRefresh < Self.refreshInterval { return }
        let task = Task { await self.performRefresh() }
        refreshInFlight = task
        await task.value
        if refreshInFlight == task { refreshInFlight = nil }
    }

    private func performRefresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        lastRefresh = ContinuousClock().now
        guard let result = await runner.run(["list"], timeout: Self.listTimeout) else {
            isAvailable = false
            hasLoaded = true
            log.error("shortcuts list could not be started")
            return
        }
        isAvailable = true
        hasLoaded = true
        guard result.exitStatus == 0, !result.timedOut else {
            let detail = ShortcutRunFailure.firstMessageLine(in: result.standardError)
            log.error("shortcuts list failed (\(result.exitStatus)): \(detail, privacy: .public)")
            return
        }
        let names = ShortcutsCatalog.names(fromListOutput: result.standardOutput)
        if names != shortcuts { shortcuts = names }
    }

    // MARK: Running

    /// Runs the shortcut named `name` and returns why it failed, or `nil` when it finished
    /// normally. ``runs`` shows it as running meanwhile. A second request for a shortcut that is
    /// already running is ignored and returns `nil`.
    @discardableResult
    public func run(_ name: String) async -> ShortcutRunFailure? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .notFound }
        if runs[trimmed]?.isRunning == true { return nil }
        runs[trimmed] = .running(since: Date())
        log.debug("Running shortcut \(trimmed, privacy: .public)")

        let failure: ShortcutRunFailure?
        if let result = await runner.run(["run", trimmed], timeout: Self.runTimeout) {
            isAvailable = true
            failure = ShortcutRunFailure.interpret(
                exitStatus: result.exitStatus, standardError: result.standardError, timedOut: result.timedOut)
        } else {
            isAvailable = false
            failure = .toolUnavailable
        }

        if let failure {
            log.error("Shortcut \(trimmed, privacy: .public) failed: \(failure.message, privacy: .public)")
            runs[trimmed] = .failed(failure, at: Date())
        } else {
            runs[trimmed] = .succeeded(at: Date())
        }
        return failure
    }

    /// Forgets the outcome shown for `name`, so the tile goes back to its resting look.
    public func clearState(of name: String) {
        guard runs[name]?.isRunning != true else { return }
        runs[name] = nil
    }
}
