import AppKit
import Foundation
import os

/// Reads Focus state from the database `donotdisturbd` keeps in `~/Library/DoNotDisturb/DB`,
/// and watches it for changes.
///
/// `Assertions.json` holds a record for the Focus that's on (none when Focus is off), and
/// `ModeConfigurations.json` describes every Focus the user has set up. Neither is
/// documented, but their shape hasn't changed from macOS 12 through 26. The folder is
/// protected by macOS: reading it needs Full Disk Access, which never prompts, so
/// `FocusReadError.accessDenied` sends the user to System Settings. The files are replaced
/// whole when they change, so the folder is watched as well as the assertions file.
@MainActor
public final class DoNotDisturbDatabase: FocusStateSource {
    public static let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB", isDirectory: true)

    private let directory: URL
    private var directorySource: (any DispatchSourceFileSystemObject)?
    private var fileSource: (any DispatchSourceFileSystemObject)?
    private var onChange: (@MainActor () -> Void)?
    private let log = Logger(subsystem: "com.newyorkcompute.opendock", category: "FocusModeMonitor")

    private var assertionsURL: URL { directory.appendingPathComponent("Assertions.json") }
    private var modesURL: URL { directory.appendingPathComponent("ModeConfigurations.json") }

    public init(directory: URL = DoNotDisturbDatabase.defaultDirectory) {
        self.directory = directory
    }

    isolated deinit {
        stopWatching()
    }

    public func readSnapshot() throws -> FocusSnapshot {
        let modes = try FocusDatabaseFormat.modes(from: read(modesURL))
        let activeModeID: String?
        do {
            activeModeID = try FocusDatabaseFormat.activeModeID(from: read(assertionsURL))
        } catch FocusReadError.unavailable where !FileManager.default.fileExists(atPath: assertionsURL.path) {
            // No assertions file has been written yet, so no Focus can be on.
            activeModeID = nil
        }
        return FocusSnapshot(modes: modes, activeModeID: activeModeID)
    }

    public func startWatching(onChange: @escaping @MainActor () -> Void) throws {
        stopWatching()
        directorySource = try makeSource(path: directory.path, events: [.write, .rename, .delete, .link, .attrib]) {
            [weak self] in
            // The assertions file is replaced on change; follow the new one.
            self?.watchAssertionsFile()
            self?.onChange?()
        }
        self.onChange = onChange
        watchAssertionsFile()
    }

    public func stopWatching() {
        directorySource?.cancel()
        directorySource = nil
        fileSource?.cancel()
        fileSource = nil
        onChange = nil
    }

    public func openAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Files

    private func read(_ url: URL) throws -> Data {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw Self.readError(errno) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            return try handle.readToEnd() ?? Data()
        } catch {
            throw FocusReadError.unavailable
        }
    }

    private func watchAssertionsFile() {
        fileSource?.cancel()
        fileSource = try? makeSource(path: assertionsURL.path, events: [.write, .extend, .delete, .rename, .attrib]) {
            [weak self] in self?.onChange?()
        }
    }

    private func makeSource(
        path: String,
        events: DispatchSource.FileSystemEvent,
        handler: @escaping @MainActor () -> Void
    ) throws -> any DispatchSourceFileSystemObject {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { throw Self.readError(errno) }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: events, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { handler() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    private nonisolated static func readError(_ code: Int32) -> FocusReadError {
        code == EPERM || code == EACCES ? .accessDenied : .unavailable
    }
}

/// The shape of the Focus database's JSON files. Pure functions, so they can be tested with
/// captured files.
public enum FocusDatabaseFormat {
    /// The Focus that's on according to `Assertions.json`, or nil when none is. With several
    /// records (a Focus turned on from two places, say), the newest wins. Throws
    /// `FocusReadError.unavailable` when the file isn't the expected JSON.
    public static func activeModeID(from data: Data) throws -> String? {
        let file = try decode(AssertionsFile.self, from: data)
        let records = (file.data ?? []).flatMap { $0.storeAssertionRecords ?? [] }
        return records.max { ($0.assertionStartDateTimestamp ?? 0) < ($1.assertionStartDateTimestamp ?? 0) }?
            .assertionDetails?.assertionDetailsModeIdentifier
    }

    /// The Focus modes set up on this Mac according to `ModeConfigurations.json`: Do Not
    /// Disturb first, then the rest by name. Throws `FocusReadError.unavailable` when the file
    /// isn't the expected JSON.
    public static func modes(from data: Data) throws -> [FocusMode] {
        let file = try decode(ModeConfigurationsFile.self, from: data)
        var modes: [FocusMode] = []
        for store in file.data ?? [] {
            for (key, configuration) in store.modeConfigurations ?? [:] {
                guard let name = configuration.mode?.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !name.isEmpty
                else { continue }
                let id = configuration.mode?.modeIdentifier ?? key
                guard !modes.contains(where: { $0.id == id }) else { continue }
                modes.append(FocusMode(id: id, name: name, symbolName: configuration.mode?.symbolImageName))
            }
        }
        return modes.sorted { lhs, rhs in
            if (lhs.id == FocusMode.doNotDisturbID) != (rhs.id == FocusMode.doNotDisturbID) {
                return lhs.id == FocusMode.doNotDisturbID
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw FocusReadError.unavailable
        }
    }

    private struct AssertionsFile: Decodable {
        var data: [Store]?

        struct Store: Decodable {
            var storeAssertionRecords: [Record]?
        }

        struct Record: Decodable {
            var assertionDetails: Details?
            var assertionStartDateTimestamp: Double?
        }

        struct Details: Decodable {
            var assertionDetailsModeIdentifier: String?
        }
    }

    private struct ModeConfigurationsFile: Decodable {
        var data: [Store]?

        struct Store: Decodable {
            var modeConfigurations: [String: Configuration]?
        }

        struct Configuration: Decodable {
            var mode: Mode?
        }

        struct Mode: Decodable {
            var name: String?
            var modeIdentifier: String?
            var symbolImageName: String?
        }
    }
}
