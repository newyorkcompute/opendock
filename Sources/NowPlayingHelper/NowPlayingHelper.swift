import AppKit
import Foundation

// The Now Playing helper.
//
// Since macOS 15.4 the private MediaRemote framework only answers processes signed by
// Apple, so OpenDock can't ask it what's playing. Apple's own `/usr/bin/perl` can, and
// Perl's DynaLoader can load any dynamic library and call a C function in it. This target
// builds that library: `SystemServices.MediaRemoteHelperProvider` starts
// `/usr/bin/perl` with a short script that loads it and calls one of the entry points
// below. The code then runs inside Perl's (Apple-signed) process, MediaRemote answers, and
// the helper writes JSON lines to stdout for the app to read (`DockCore.NowPlayingHelperMessage`).
//
// This library is bundled with the app but never linked into it. Nothing in here may
// assume AppKit's main run loop or a GUI session.
//
// Entry points (called by Perl with XS arguments, which are ignored):
// - `opendock_nowplaying_stream`: prints the state now and on every change until stdin
//   closes. Lines read from stdin are commands: play, pause, toggle, next, previous, refresh.
// - `opendock_nowplaying_get`: prints the state once and exits.
// - `opendock_nowplaying_send`: sends the command named in $OPENDOCK_NOWPLAYING_COMMAND and exits.

@_cdecl("opendock_nowplaying_stream")
public func nowPlayingStreamEntryPoint() {
    Helper.shared.stream()
}

@_cdecl("opendock_nowplaying_get")
public func nowPlayingGetEntryPoint() {
    Helper.shared.getOnce()
}

@_cdecl("opendock_nowplaying_send")
public func nowPlayingSendEntryPoint() {
    let name = ProcessInfo.processInfo.environment["OPENDOCK_NOWPLAYING_COMMAND"] ?? ""
    Helper.shared.sendOnce(commandNamed: name)
}

// MARK: - MediaRemote

/// The handful of MediaRemote functions the helper needs, looked up with `dlsym` so the
/// library doesn't link against a private framework.
private final class MediaRemote: @unchecked Sendable {
    typealias RegisterForNotifications = @convention(c) (DispatchQueue) -> Void
    typealias GetNowPlayingInfo =
        @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    typealias GetIsPlaying = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
    typealias GetApplicationPID = @convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void
    typealias SendCommand = @convention(c) (Int32, CFDictionary?) -> Bool

    let registerForNotifications: RegisterForNotifications
    let getNowPlayingInfo: GetNowPlayingInfo
    let getIsPlaying: GetIsPlaying
    let getApplicationPID: GetApplicationPID
    let sendCommand: SendCommand

    /// MRCommand values.
    enum Command: Int32 {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5

        init?(name: String) {
            switch name.lowercased() {
            case "play": self = .play
            case "pause": self = .pause
            case "toggle", "toggleplaypause": self = .togglePlayPause
            case "next", "nexttrack": self = .nextTrack
            case "previous", "previoustrack": self = .previousTrack
            default: return nil
            }
        }
    }

    enum Key {
        static let title = "kMRMediaRemoteNowPlayingInfoTitle"
        static let artist = "kMRMediaRemoteNowPlayingInfoArtist"
        static let album = "kMRMediaRemoteNowPlayingInfoAlbum"
        static let duration = "kMRMediaRemoteNowPlayingInfoDuration"
        static let elapsedTime = "kMRMediaRemoteNowPlayingInfoElapsedTime"
        static let timestamp = "kMRMediaRemoteNowPlayingInfoTimestamp"
        static let playbackRate = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
        static let artworkData = "kMRMediaRemoteNowPlayingInfoArtworkData"
        static let artworkMIMEType = "kMRMediaRemoteNowPlayingInfoArtworkMIMEType"
    }

    static let notificationNames = [
        "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        "kMRMediaRemoteNowPlayingPlaybackQueueDidChangeNotification",
    ]

    init?() {
        guard
            let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)
        else { return nil }
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        guard
            let register = symbol("MRMediaRemoteRegisterForNowPlayingNotifications", as: RegisterForNotifications.self),
            let info = symbol("MRMediaRemoteGetNowPlayingInfo", as: GetNowPlayingInfo.self),
            let playing = symbol("MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: GetIsPlaying.self),
            let pid = symbol("MRMediaRemoteGetNowPlayingApplicationPID", as: GetApplicationPID.self),
            let send = symbol("MRMediaRemoteSendCommand", as: SendCommand.self)
        else { return nil }
        registerForNotifications = register
        getNowPlayingInfo = info
        getIsPlaying = playing
        getApplicationPID = pid
        sendCommand = send
    }
}

// MARK: - Helper

/// Reads the Now Playing state and writes it to stdout. All state lives on `queue`;
/// MediaRemote delivers its callbacks on `callbackQueue` so a read can block `queue`
/// while it waits for them.
private final class Helper: @unchecked Sendable {
    static let shared = Helper()

    private let queue = DispatchQueue(label: "com.newyorkcompute.opendock.nowplaying-helper")
    private let callbackQueue = DispatchQueue(label: "com.newyorkcompute.opendock.nowplaying-helper.mediaremote")
    private var mediaRemote: MediaRemote?
    private var lastPayload: [String: Any] = [:]
    private var lastArtworkHash: Int?
    private var pendingRefresh: DispatchWorkItem?
    private var observers: [any NSObjectProtocol] = []
    private var safetyNet: (any DispatchSourceTimer)?

    /// How long to wait for MediaRemote before giving up on one snapshot.
    private let timeout: DispatchTimeInterval = .seconds(2)

    // MARK: Entry points

    func stream() {
        guard let mediaRemote = loadMediaRemote() else { return }
        mediaRemote.registerForNotifications(callbackQueue)
        for name in MediaRemote.notificationNames {
            let observer = NotificationCenter.default.addObserver(
                forName: Notification.Name(name), object: nil, queue: nil
            ) { [weak self] _ in
                self?.scheduleRefresh()
            }
            observers.append(observer)
        }

        // Notifications occasionally go missing (sleep/wake, a player quitting), so re-read
        // the state every so often. This is the only polling the helper does.
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 15, repeating: 15, leeway: .seconds(2))
        timer.setEventHandler { [weak self] in self?.refresh(force: false) }
        timer.resume()
        safetyNet = timer

        readCommandsFromStandardInput()
        queue.async { self.refresh(force: true) }
        dispatchMain()
    }

    func getOnce() {
        guard loadMediaRemote() != nil else { return }
        queue.async {
            self.refresh(force: true)
            exit(0)
        }
        dispatchMain()
    }

    func sendOnce(commandNamed name: String) {
        guard let mediaRemote = loadMediaRemote() else { return }
        guard let command = MediaRemote.Command(name: name) else {
            fail("Unknown command '\(name)'", status: 2)
        }
        queue.async {
            guard mediaRemote.sendCommand(command.rawValue, nil) else {
                self.fail("MediaRemote refused command '\(name)'", status: 3)
            }
            // The command is an XPC message; wait for a round trip so it's delivered before exiting.
            let done = DispatchSemaphore(value: 0)
            mediaRemote.getApplicationPID(self.callbackQueue) { _ in done.signal() }
            _ = done.wait(timeout: .now() + self.timeout)
            exit(0)
        }
        dispatchMain()
    }

    // MARK: Setup

    private func loadMediaRemote() -> MediaRemote? {
        signal(SIGPIPE, SIG_IGN)
        guard let mediaRemote = MediaRemote() else {
            fail("MediaRemote.framework is missing or has changed", status: 4)
        }
        self.mediaRemote = mediaRemote
        return mediaRemote
    }

    private func fail(_ message: String, status: Int32) -> Never {
        try? FileHandle.standardError.write(contentsOf: Data((message + "\n").utf8))
        exit(status)
    }

    /// Commands arrive one per line on stdin. EOF means the app went away.
    private func readCommandsFromStandardInput() {
        let thread = Thread { [weak self] in
            while let line = readLine(strippingNewline: true) {
                let command = line.trimmingCharacters(in: .whitespaces)
                guard !command.isEmpty, let self else { continue }
                self.queue.async { self.handle(command: command) }
            }
            exit(0)
        }
        thread.name = "stdin"
        thread.start()
    }

    private func handle(command name: String) {
        if name == "refresh" {
            refresh(force: true)
            return
        }
        guard let mediaRemote, let command = MediaRemote.Command(name: name) else { return }
        _ = mediaRemote.sendCommand(command.rawValue, nil)
        // Players post a change notification, but not all of them do so promptly.
        queue.asyncAfter(deadline: .now() + .milliseconds(400)) { [weak self] in self?.refresh(force: false) }
    }

    // MARK: Reading the state

    /// Coalesces bursts of notifications (a track change fires several) into one read.
    private func scheduleRefresh() {
        queue.async {
            self.pendingRefresh?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.refresh(force: false) }
            self.pendingRefresh = work
            self.queue.asyncAfter(deadline: .now() + .milliseconds(150), execute: work)
        }
    }

    /// Reads PID, playing flag and info, then prints a message if anything changed
    /// (or always, when `force` is set).
    private func refresh(force: Bool) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let mediaRemote else { return }

        let group = DispatchGroup()
        let state = Snapshot()

        group.enter()
        mediaRemote.getApplicationPID(callbackQueue) { pid in
            state.pid = pid
            group.leave()
        }
        group.enter()
        mediaRemote.getIsPlaying(callbackQueue) { playing in
            state.isPlaying = playing
            group.leave()
        }
        group.enter()
        mediaRemote.getNowPlayingInfo(callbackQueue) { info in
            if let info, let dictionary = (info as NSDictionary) as? [String: Any] {
                state.info = dictionary
            }
            group.leave()
        }

        guard group.wait(timeout: .now() + timeout) == .success else { return }
        let (payload, artworkHash) = makePayload(from: state)
        emit(payload: payload, artworkHash: artworkHash, force: force)
    }

    private final class Snapshot: @unchecked Sendable {
        var pid: Int32 = 0
        var isPlaying = false
        var info: [String: Any] = [:]
    }

    /// Builds the JSON payload. Artwork bytes are included only when they differ from the
    /// last emitted artwork; the hash of the current artwork comes back separately.
    private func makePayload(from state: Snapshot) -> (payload: [String: Any], artworkHash: Int?) {
        let info = state.info
        guard state.pid > 0, let title = info[MediaRemote.Key.title] as? String, !title.isEmpty else {
            return (["kind": "idle"], nil)
        }

        var payload: [String: Any] = [
            "kind": "nowPlaying",
            "pid": Int(state.pid),
            "playing": state.isPlaying,
            "title": title,
        ]
        if let bundleID = NSRunningApplication(processIdentifier: state.pid)?.bundleIdentifier {
            payload["bundleIdentifier"] = bundleID
        }
        if let artist = info[MediaRemote.Key.artist] as? String { payload["artist"] = artist }
        if let album = info[MediaRemote.Key.album] as? String { payload["album"] = album }
        if let duration = info[MediaRemote.Key.duration] as? Double { payload["duration"] = duration }
        if let elapsed = info[MediaRemote.Key.elapsedTime] as? Double { payload["elapsed"] = elapsed }
        if let timestamp = info[MediaRemote.Key.timestamp] as? Date {
            payload["timestamp"] = timestamp.timeIntervalSince1970
        }
        if let rate = info[MediaRemote.Key.playbackRate] as? Double { payload["rate"] = rate }

        var artworkHash: Int?
        if let artwork = info[MediaRemote.Key.artworkData] as? Data, !artwork.isEmpty {
            payload["hasArtwork"] = true
            artworkHash = artwork.hashValue
            if artworkHash != lastArtworkHash {
                payload["artworkData"] = artwork.base64EncodedString()
                if let mime = info[MediaRemote.Key.artworkMIMEType] as? String { payload["artworkMimeType"] = mime }
            }
        } else {
            payload["hasArtwork"] = false
        }
        return (payload, artworkHash)
    }

    private func emit(payload: [String: Any], artworkHash: Int?, force: Bool) {
        var comparable = payload
        comparable["artworkData"] = nil
        comparable["artworkMimeType"] = nil
        let artworkChanged = artworkHash != lastArtworkHash
        guard force || artworkChanged || !NSDictionary(dictionary: comparable).isEqual(to: lastPayload) else { return }
        lastPayload = comparable
        lastArtworkHash = artworkHash

        guard JSONSerialization.isValidJSONObject(payload),
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        else { return }
        do {
            try FileHandle.standardOutput.write(contentsOf: data + Data("\n".utf8))
        } catch {
            // stdout is gone: the app has exited.
            exit(0)
        }
    }
}
