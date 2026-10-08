import Foundation
import Testing

@testable import SystemServices

/// Stands in for the Focus database.
@MainActor
final class FakeFocusStateSource: FocusStateSource {
    var snapshot: FocusSnapshot
    var error: FocusReadError?
    var watchError: FocusReadError?
    var reads = 0
    var settingsOpened = 0
    private(set) var onChange: (@MainActor () -> Void)?
    var isWatching: Bool { onChange != nil }

    init(snapshot: FocusSnapshot = FocusSnapshot(), error: FocusReadError? = nil) {
        self.snapshot = snapshot
        self.error = error
    }

    func readSnapshot() throws -> FocusSnapshot {
        reads += 1
        if let error { throw error }
        return snapshot
    }

    func startWatching(onChange: @escaping @MainActor () -> Void) throws {
        if let watchError { throw watchError }
        self.onChange = onChange
    }

    func stopWatching() { onChange = nil }

    func openAccessSettings() { settingsOpened += 1 }

    /// What the database does when a Focus changes: the file is rewritten and the watcher fires.
    func change(to activeModeID: String?) {
        snapshot.activeModeID = activeModeID
        onChange?()
    }
}

private let work = FocusMode(id: "com.apple.focus.work", name: "Work", symbolName: "person.lanyardcard.fill")
private let doNotDisturb = FocusMode(id: FocusMode.doNotDisturbID, name: "Do Not Disturb", symbolName: "moon.fill")

@Suite("Focus database format")
struct FocusDatabaseFormatTests {
    /// `Assertions.json` with Work on, as written by macOS 15 and 26 (fields not read are left out).
    private let workOn = #"""
        {
          "data" : [
            {
              "storeAssertionRecords" : [
                {
                  "assertionDetails" : {
                    "assertionDetailsIdentifier" : "C5A2B1E0-3F2D-4A6B-9C8D-7E6F5A4B3C2D",
                    "assertionDetailsModeIdentifier" : "com.apple.focus.work",
                    "assertionDetailsReason" : "user-action",
                    "assertionDetailsUserRequested" : true
                  },
                  "assertionClientIdentifier" : "com.apple.controlcenter",
                  "assertionStartDateTimestamp" : 781234567.123,
                  "assertionUUID" : "2A9B8C7D-6E5F-4A3B-2C1D-0E9F8A7B6C5D"
                }
              ],
              "storeInvalidationRecords" : [ ],
              "storeInvalidationRequestRecords" : [ ]
            }
          ],
          "version" : 1
        }
        """#

    private let modeConfigurations = #"""
        {
          "data" : [
            {
              "modeConfigurations" : {
                "com.apple.focus.work" : {
                  "automaticallyGenerated" : false,
                  "mode" : {
                    "identifier" : "9B1D0E2F-3A4B-4C5D-8E6F-7A8B9C0D1E2F",
                    "modeIdentifier" : "com.apple.focus.work",
                    "name" : "Work",
                    "semanticType" : 4,
                    "symbolImageName" : "person.lanyardcard.fill",
                    "tintColorName" : "systemTealColor",
                    "visibility" : 0
                  },
                  "triggers" : { "triggers" : [ ] }
                },
                "com.apple.donotdisturb.mode.default" : {
                  "mode" : {
                    "identifier" : "1C2D3E4F-5A6B-4C7D-8E9F-0A1B2C3D4E5F",
                    "modeIdentifier" : "com.apple.donotdisturb.mode.default",
                    "name" : "Do Not Disturb",
                    "semanticType" : 0,
                    "symbolImageName" : "moon.fill",
                    "tintColorName" : "systemIndigoColor"
                  }
                },
                "com.apple.donotdisturb.mode.graduationcap.fill" : {
                  "mode" : {
                    "modeIdentifier" : "com.apple.donotdisturb.mode.graduationcap.fill",
                    "name" : "Studying",
                    "symbolImageName" : "graduationcap.fill"
                  }
                },
                "com.apple.focus.unnamed" : {
                  "mode" : { "modeIdentifier" : "com.apple.focus.unnamed", "name" : "  " }
                }
              }
            }
          ],
          "version" : 1
        }
        """#

    @Test func readsTheActiveFocus() throws {
        #expect(try FocusDatabaseFormat.activeModeID(from: Data(workOn.utf8)) == "com.apple.focus.work")
    }

    @Test func noRecordsMeansNoFocus() throws {
        let off = #"{"data":[{"storeAssertionRecords":[],"storeInvalidationRecords":[]}],"version":1}"#
        #expect(try FocusDatabaseFormat.activeModeID(from: Data(off.utf8)) == nil)
        let missing = #"{"data":[{"storeInvalidationRecords":[]}],"version":1}"#
        #expect(try FocusDatabaseFormat.activeModeID(from: Data(missing.utf8)) == nil)
        #expect(try FocusDatabaseFormat.activeModeID(from: Data(#"{"data":[],"version":1}"#.utf8)) == nil)
    }

    @Test func theNewestOfSeveralRecordsWins() throws {
        let two = #"""
            {"data":[{"storeAssertionRecords":[
              {"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.focus.work"},"assertionStartDateTimestamp":100},
              {"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.sleep.sleep-mode"},"assertionStartDateTimestamp":200},
              {"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.focus.personal"}}
            ]}]}
            """#
        #expect(try FocusDatabaseFormat.activeModeID(from: Data(two.utf8)) == "com.apple.sleep.sleep-mode")
    }

    @Test func listsModesWithDoNotDisturbFirstThenByName() throws {
        let modes = try FocusDatabaseFormat.modes(from: Data(modeConfigurations.utf8))
        #expect(modes.map(\.name) == ["Do Not Disturb", "Studying", "Work"])
        #expect(modes[0] == doNotDisturb)
        #expect(modes[2] == work)
        #expect(modes[1].id == "com.apple.donotdisturb.mode.graduationcap.fill")
    }

    @Test func aFileThatIsNotTheDatabaseIsUnavailable() throws {
        #expect(throws: FocusReadError.unavailable) {
            try FocusDatabaseFormat.activeModeID(from: Data("not json".utf8))
        }
        #expect(throws: FocusReadError.unavailable) {
            try FocusDatabaseFormat.modes(from: Data())
        }
        #expect(try FocusDatabaseFormat.modes(from: Data(#"{"version":1}"#.utf8)).isEmpty)
    }
}

@Suite("FocusModeMonitor")
@MainActor
struct FocusModeMonitorTests {
    /// Long enough for a scheduled read to have happened, well short of a retry.
    private func settle() async {
        try? await Task.sleep(for: FocusModeMonitor.changeDelay * 2)
    }

    @Test func readsAndWatchesOnStart() async {
        let source = FakeFocusStateSource(snapshot: FocusSnapshot(modes: [doNotDisturb, work], activeModeID: work.id))
        let monitor = FocusModeMonitor(source: source)
        #expect(monitor.access == .unknown)
        monitor.start()
        #expect(monitor.access == .granted)
        #expect(monitor.modes == [doNotDisturb, work])
        #expect(monitor.activeModeID == work.id)
        #expect(monitor.activeMode == work)
        #expect(source.isWatching)

        source.change(to: nil)
        #expect(monitor.activeModeID == work.id, "a change is read after a short delay, not at once")
        await settle()
        #expect(monitor.activeModeID == nil)
        #expect(monitor.activeMode == nil)

        source.change(to: doNotDisturb.id)
        await settle()
        #expect(monitor.activeMode == doNotDisturb)
        monitor.stop()
        #expect(!source.isWatching)
    }

    @Test func severalEventsForOneChangeAreReadOnce() async {
        let source = FakeFocusStateSource(snapshot: FocusSnapshot(modes: [work]))
        let monitor = FocusModeMonitor(source: source)
        monitor.start()
        let readsAfterStart = source.reads
        source.change(to: work.id)
        source.change(to: work.id)
        source.change(to: work.id)
        await settle()
        #expect(source.reads == readsAfterStart + 1)
        #expect(monitor.activeModeID == work.id)
    }

    @Test func withoutAccessNothingIsWatched() {
        let source = FakeFocusStateSource(snapshot: FocusSnapshot(modes: [work], activeModeID: work.id))
        source.error = .accessDenied
        let monitor = FocusModeMonitor(source: source)
        monitor.start()
        #expect(monitor.access == .denied)
        #expect(monitor.modes.isEmpty)
        #expect(monitor.activeModeID == nil)
        #expect(!source.isWatching)

        monitor.openAccessSettings()
        #expect(source.settingsOpened == 1)

        // Access granted and OpenDock relaunched, or the user came back to Settings.
        source.error = nil
        monitor.refresh()
        #expect(monitor.access == .granted)
        #expect(monitor.activeModeID == work.id)
        #expect(source.isWatching)
    }

    @Test func losingAccessClearsTheState() async {
        let source = FakeFocusStateSource(snapshot: FocusSnapshot(modes: [work], activeModeID: work.id))
        let monitor = FocusModeMonitor(source: source)
        monitor.start()
        source.error = .accessDenied
        source.change(to: nil)
        await settle()
        #expect(monitor.access == .denied)
        #expect(monitor.activeModeID == nil)
        #expect(!source.isWatching)
    }

    @Test func aReadThatFailsMidWriteIsRetried() async {
        let source = FakeFocusStateSource(snapshot: FocusSnapshot(modes: [work]))
        let monitor = FocusModeMonitor(source: source)
        monitor.start()
        source.snapshot.activeModeID = work.id
        source.error = .unavailable
        source.onChange?()
        await settle()
        #expect(monitor.access == .granted, "one failed read doesn't give up")
        source.error = nil
        try? await Task.sleep(for: FocusModeMonitor.retryDelay * 2)
        #expect(monitor.activeModeID == work.id)
    }

    @Test func noDatabaseIsUnavailable() {
        let source = FakeFocusStateSource(error: .unavailable)
        let monitor = FocusModeMonitor(source: source)
        monitor.start()
        #expect(monitor.access == .unavailable)
        #expect(!source.isWatching)
    }

    @Test func anUnknownActiveFocusIsStillReported() {
        let source = FakeFocusStateSource(snapshot: FocusSnapshot(modes: [work], activeModeID: "com.apple.focus.new"))
        let monitor = FocusModeMonitor(source: source)
        monitor.start()
        #expect(monitor.activeMode?.id == "com.apple.focus.new")
    }
}

@Suite("DoNotDisturbDatabase")
@MainActor
struct DoNotDisturbDatabaseTests {
    private func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("opendock-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private let modes = #"""
        {"data":[{"modeConfigurations":{"com.apple.focus.work":{"mode":{"modeIdentifier":"com.apple.focus.work","name":"Work"}}}}]}
        """#

    @Test func readsTheFilesInAFolder() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(modes.utf8).write(to: dir.appendingPathComponent("ModeConfigurations.json"))

        let database = DoNotDisturbDatabase(directory: dir)
        // No assertions file yet: no Focus is on.
        #expect(try database.readSnapshot() == FocusSnapshot(modes: [work.withoutSymbol], activeModeID: nil))

        let on =
            #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.focus.work"}}]}]}"#
        try Data(on.utf8).write(to: dir.appendingPathComponent("Assertions.json"))
        #expect(try database.readSnapshot().activeModeID == "com.apple.focus.work")
    }

    @Test func aMissingFolderIsUnavailable() throws {
        let dir = try temporaryDirectory().appendingPathComponent("missing", isDirectory: true)
        let database = DoNotDisturbDatabase(directory: dir)
        #expect(throws: FocusReadError.unavailable) { try database.readSnapshot() }
        #expect(throws: FocusReadError.unavailable) { try database.startWatching {} }
    }

    @Test func noticesWhenTheAssertionsFileIsReplaced() async throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(modes.utf8).write(to: dir.appendingPathComponent("ModeConfigurations.json"))
        let assertions = dir.appendingPathComponent("Assertions.json")
        try Data(#"{"data":[{}]}"#.utf8).write(to: assertions)

        let database = DoNotDisturbDatabase(directory: dir)
        let changes = Counter()
        try database.startWatching { changes.increment() }
        defer { database.stopWatching() }

        // Atomic replacement, as donotdisturbd does it.
        try Data(#"{"data":[{"storeAssertionRecords":[]}]}"#.utf8).write(to: assertions, options: .atomic)
        try await waitUntil { changes.value > 0 }
        let afterReplace = changes.value

        // In-place rewrite of the new file.
        let handle = try FileHandle(forWritingTo: assertions)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(" ".utf8))
        try handle.close()
        try await waitUntil { changes.value > afterReplace }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0 ..< 100 where !condition() {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(condition())
    }
}

@MainActor
private final class Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

extension FocusMode {
    fileprivate var withoutSymbol: FocusMode { FocusMode(id: id, name: name) }
}
