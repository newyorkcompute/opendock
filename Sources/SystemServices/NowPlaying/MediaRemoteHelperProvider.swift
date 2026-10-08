import DockCore
import Foundation
import os

/// Reads the system-wide Now Playing state (any player: Music, Spotify, browsers, ...)
/// through the bundled Now Playing helper library, run inside `/usr/bin/perl`.
///
/// MediaRemote, the private framework behind Control Center's Now Playing, stopped
/// answering third-party processes in macOS 15.4. Apple-signed `/usr/bin/perl` is still
/// allowed to use it, and Perl can load a dynamic library and call a C function in it.
/// So this provider launches Perl with a short script that loads
/// `libOpenDockNowPlayingHelper.dylib` (the `NowPlayingHelper` target) and calls its
/// `stream` entry point. The helper prints one JSON line per change
/// (`NowPlayingHelperMessage`) and reads transport commands from stdin. If the helper
/// exits, it is restarted with a growing delay; if it can't run at all, the provider
/// reports `.failed` so the monitor can fall back to scripting players directly.
@MainActor
public final class MediaRemoteHelperProvider: NowPlayingProvider {
    public nonisolated static let perlURL = URL(fileURLWithPath: "/usr/bin/perl")
    /// File name of the helper library, as `scripts/build-app.sh` copies it into `Contents/Frameworks`.
    public nonisolated static let libraryName = "libOpenDockNowPlayingHelper.dylib"

    /// Loads the library and calls one entry point. Perl's `DynaLoader` hands the function
    /// XS arguments, which the helper ignores. `$|` turns off output buffering.
    nonisolated static let perlScript = """
        use strict; use warnings; use DynaLoader;
        $| = 1;
        my ($library, $function) = @ARGV;
        my $handle = DynaLoader::dl_load_file($library, 0)
            or die "cannot load $library: " . DynaLoader::dl_error() . "\\n";
        my $symbol = DynaLoader::dl_find_symbol($handle, $function)
            || DynaLoader::dl_find_symbol($handle, "_$function")
            or die "no $function in $library: " . DynaLoader::dl_error() . "\\n";
        DynaLoader::dl_install_xsub("main::entry", $symbol);
        &main::entry();
        """

    /// Exit status the helper uses when MediaRemote itself is missing or has changed.
    nonisolated static let mediaRemoteMissingStatus: Int32 = 4

    public let sourceName = "the system's Now Playing"

    private let libraryURL: URL
    private let perlURL: URL
    private let logger = Logger(subsystem: "com.newyorkcompute.opendock", category: "NowPlayingHelper")

    private var handler: (@MainActor (NowPlayingProviderEvent) -> Void)?
    private var process: Process?
    private var commandPipe: Pipe?
    private var track: NowPlayingTrack?
    private var restartTask: Task<Void, Never>?
    private var restartDelay: Duration = .seconds(1)
    private var launchedAt: ContinuousClock.Instant?
    private var quickExits = 0
    /// Incremented per launch so callbacks from an old process are ignored.
    private var generation = 0

    /// Finds the helper library next to the app: in `Contents/Frameworks` of the bundle, or,
    /// when running the bare binary from `swift build`, next to the executable.
    public nonisolated static func locateLibrary(bundle: Bundle = .main) -> URL? {
        var candidates: [URL] = []
        if let frameworks = bundle.privateFrameworksURL {
            candidates.append(frameworks.appendingPathComponent(libraryName))
        }
        if let executable = bundle.executableURL {
            candidates.append(executable.deletingLastPathComponent().appendingPathComponent(libraryName))
        }
        return candidates.first { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    /// `nil` when Perl or the helper library can't be found; the monitor then skips this provider.
    public init?(libraryURL: URL? = MediaRemoteHelperProvider.locateLibrary(), perlURL: URL = perlURL) {
        guard let libraryURL, FileManager.default.isExecutableFile(atPath: perlURL.path) else { return nil }
        self.libraryURL = libraryURL
        self.perlURL = perlURL
    }

    isolated deinit {
        stop()
    }

    // MARK: NowPlayingProvider

    public func start(handler: @escaping @MainActor (NowPlayingProviderEvent) -> Void) {
        self.handler = handler
        resetRestartBackoff()
        launch()
    }

    public func stop() {
        handler = nil
        restartTask?.cancel()
        restartTask = nil
        tearDownProcess()
        track = nil
    }

    public func send(_ command: NowPlayingCommand) {
        let name = Self.helperName(for: command)
        if let commandPipe, process?.isRunning == true {
            do {
                try commandPipe.fileHandleForWriting.write(contentsOf: Data((name + "\n").utf8))
                return
            } catch {
                logger.error(
                    "Writing \(name, privacy: .public) to the helper failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        // No stream running: send through a short-lived helper instead.
        let oneShot = makeProcess(entryPoint: "opendock_nowplaying_send")
        oneShot.environment = ProcessInfo.processInfo.environment.merging(["OPENDOCK_NOWPLAYING_COMMAND": name]) {
            _, new in new
        }
        oneShot.standardOutput = FileHandle.nullDevice
        oneShot.standardError = FileHandle.nullDevice
        do {
            try oneShot.run()
        } catch {
            logger.error(
                "Launching the helper for \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    public func setDockVisible(_ visible: Bool) {
        // The helper is event-driven; nothing to slow down.
    }

    // MARK: Process

    static func helperName(for command: NowPlayingCommand) -> String {
        switch command {
        case .play: "play"
        case .pause: "pause"
        case .togglePlayPause: "toggle"
        case .nextTrack: "next"
        case .previousTrack: "previous"
        }
    }

    private func makeProcess(entryPoint: String) -> Process {
        let process = Process()
        process.executableURL = perlURL
        process.arguments = ["-e", Self.perlScript, "--", libraryURL.path, entryPoint]
        return process
    }

    private func launch() {
        guard handler != nil, process == nil else { return }
        let process = makeProcess(entryPoint: "opendock_nowplaying_stream")
        let output = Pipe()
        let input = Pipe()
        process.standardOutput = output
        process.standardInput = input
        process.standardError = FileHandle.nullDevice

        generation += 1
        let launchGeneration = generation
        let lines = LockedLineBuffer()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            let received = lines.append(data)
            guard !received.isEmpty else { return }
            // Keep the main queue's FIFO order, which detached tasks don't guarantee.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.receive(lines: received, generation: launchGeneration) }
            }
        }
        process.terminationHandler = { [weak self] exited in
            let status = exited.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.processDidExit(status: status, generation: launchGeneration) }
            }
        }

        do {
            try process.run()
        } catch {
            logger.error("Launching the Now Playing helper failed: \(error.localizedDescription, privacy: .public)")
            handler?(.failed("The Now Playing helper could not be launched."))
            return
        }
        self.process = process
        commandPipe = input
        launchedAt = ContinuousClock.now
        logger.debug("Now Playing helper started (pid \(process.processIdentifier))")
    }

    private func tearDownProcess() {
        guard let process else { return }
        self.process = nil
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        try? commandPipe?.fileHandleForWriting.close()
        commandPipe = nil
        if process.isRunning { process.terminate() }
    }

    private func receive(lines: [String], generation: Int) {
        guard generation == self.generation, process != nil, let handler else { return }
        for line in lines {
            guard let message = NowPlayingHelperMessage.parse(line: line) else { continue }
            // The helper is talking, so the next restart (if any) can be quick again.
            restartDelay = .seconds(1)
            let updated = message.track(previous: track)
            if updated != track {
                track = updated
                handler(.track(updated))
            }
        }
    }

    private func processDidExit(status: Int32, generation: Int) {
        guard generation == self.generation, process != nil else { return }
        process = nil
        commandPipe = nil
        guard let handler else { return }
        logger.notice("Now Playing helper exited with status \(status)")

        if track != nil {
            track = nil
            handler(.track(nil))
        }

        if status == Self.mediaRemoteMissingStatus {
            handler(.failed("MediaRemote is not available on this system."))
            return
        }
        if let launchedAt, ContinuousClock.now - launchedAt < .seconds(5) {
            quickExits += 1
            if quickExits >= 3 {
                handler(.failed("The Now Playing helper keeps exiting (status \(status))."))
                return
            }
        } else {
            quickExits = 0
        }

        let delay = restartDelay
        restartDelay = min(restartDelay * 2, .seconds(60))
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.launch()
        }
    }

    private func resetRestartBackoff() {
        restartDelay = .seconds(1)
        quickExits = 0
    }
}

/// A `LineBuffer` that can be fed from the pipe's reader thread.
private final class LockedLineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = LineBuffer()

    func append(_ data: Data) -> [String] {
        lock.withLock { buffer.append(data) }
    }
}
