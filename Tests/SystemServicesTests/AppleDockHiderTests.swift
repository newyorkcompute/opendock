import Foundation
import Testing
@testable import SystemServices

/// In-memory stand-in for `com.apple.dock` and the backup file.
@MainActor
final class FakeAppleDockBackend: AppleDockBackend {
    var dock: AppleDockPreferences
    var backup: AppleDockBackup?
    var restarts = 0
    var failSavingBackup = false

    init(dock: AppleDockPreferences = AppleDockPreferences()) {
        self.dock = dock
    }

    func readDockPreferences() -> AppleDockPreferences { dock }
    func writeDockPreferences(_ preferences: AppleDockPreferences) { dock = preferences }
    func restartDock() { restarts += 1 }
    func loadBackup() -> AppleDockBackup? { backup }

    func saveBackup(_ backup: AppleDockBackup) throws {
        if failSavingBackup { throw CocoaError(.fileWriteNoPermission) }
        self.backup = backup
    }

    func clearBackup() { backup = nil }
}

@MainActor
@Suite("AppleDockHider")
struct AppleDockHiderTests {
    private let userDock = AppleDockPreferences(autohide: false, autohideDelay: 0.2)

    @Test func hideSavesOriginalBeforeChangingTheDock() {
        let backend = FakeAppleDockBackend(dock: userDock)
        AppleDockHider(backend: backend).hide()
        #expect(backend.backup == AppleDockBackup(original: userDock, applied: .hidden))
        #expect(backend.dock == .hidden)
        #expect(backend.restarts == 1)
    }

    @Test func hideIsIdempotent() {
        let backend = FakeAppleDockBackend(dock: userDock)
        let hider = AppleDockHider(backend: backend)
        hider.hide()
        hider.hide()
        #expect(backend.backup?.original == userDock)
        #expect(backend.restarts == 1)
    }

    @Test func restoreAfterHideRoundTrips() {
        let backend = FakeAppleDockBackend(dock: userDock)
        let hider = AppleDockHider(backend: backend)
        hider.hide()
        hider.restore()
        #expect(backend.dock == userDock)
        #expect(backend.backup == nil)
        #expect(backend.restarts == 2)
    }

    @Test func restoreRemovesKeysThatWereUnset() {
        let backend = FakeAppleDockBackend()
        let hider = AppleDockHider(backend: backend)
        hider.hide()
        hider.restore()
        #expect(backend.dock == AppleDockPreferences())
    }

    @Test func restoreWithoutBackupDoesNothing() {
        let backend = FakeAppleDockBackend(dock: userDock)
        AppleDockHider(backend: backend).restore()
        #expect(backend.dock == userDock)
        #expect(backend.restarts == 0)
    }

    @Test func restoreKeepsValuesTheUserChangedWhileHidden() {
        let backend = FakeAppleDockBackend(dock: userDock)
        let hider = AppleDockHider(backend: backend)
        hider.hide()
        backend.dock.autohide = false
        hider.restore()
        #expect(backend.dock == userDock)
        #expect(backend.restarts == 2)

        backend.dock = AppleDockPreferences(autohide: true, autohideDelay: 0)
        hider.hide()
        backend.dock.autohideDelay = 0.5
        hider.restore()
        #expect(backend.dock == AppleDockPreferences(autohide: true, autohideDelay: 0.5))
    }

    @Test func restoreSkipsDockRestartWhenNothingChanges() {
        let backend = FakeAppleDockBackend(dock: userDock)
        let hider = AppleDockHider(backend: backend)
        hider.hide()
        backend.dock = userDock
        hider.restore()
        #expect(backend.restarts == 1)
        #expect(backend.backup == nil)
    }

    @Test func launchAfterCrashRestoresWhenOptionIsOff() {
        let backend = FakeAppleDockBackend(dock: userDock)
        AppleDockHider(backend: backend).hide()

        let relaunched = AppleDockHider(backend: backend)
        relaunched.apply(hide: false)
        #expect(backend.dock == userDock)
        #expect(backend.backup == nil)
    }

    @Test func launchAfterCrashKeepsOriginalWhenOptionIsOn() {
        let backend = FakeAppleDockBackend(dock: userDock)
        AppleDockHider(backend: backend).hide()

        let relaunched = AppleDockHider(backend: backend)
        relaunched.apply(hide: true)
        #expect(backend.restarts == 1)
        #expect(backend.backup?.original == userDock)

        relaunched.apply(hide: false)
        #expect(backend.dock == userDock)
    }

    @Test func launchAfterCrashRehidesIfTheDockWasBroughtBack() {
        let backend = FakeAppleDockBackend(dock: userDock)
        AppleDockHider(backend: backend).hide()
        backend.dock.autohide = false

        let relaunched = AppleDockHider(backend: backend)
        relaunched.apply(hide: true)
        #expect(backend.dock == .hidden)
        #expect(backend.backup?.original == userDock)
    }

    @Test func doesNotTouchTheDockIfTheBackupCannotBeSaved() {
        let backend = FakeAppleDockBackend(dock: userDock)
        backend.failSavingBackup = true
        AppleDockHider(backend: backend).hide()
        #expect(backend.dock == userDock)
        #expect(backend.restarts == 0)
    }

    @Test func neverRestoresTheHiddenDelay() {
        let leftover = AppleDockPreferences(autohide: true, autohideDelay: AppleDockPreferences.hidden.autohideDelay)
        let backend = FakeAppleDockBackend(dock: leftover)
        let hider = AppleDockHider(backend: backend)
        hider.hide()
        #expect(backend.restarts == 0)
        hider.restore()
        #expect(backend.dock == AppleDockPreferences(autohide: true, autohideDelay: nil))
    }
}

@Suite("SystemAppleDockBackend backup file")
struct AppleDockBackupFileTests {
    @MainActor
    @Test func backupRoundTripsThroughDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("apple-dock-backup.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let backend = SystemAppleDockBackend(backupURL: url)
        #expect(backend.loadBackup() == nil)

        let backup = AppleDockBackup(original: AppleDockPreferences(autohide: false), applied: .hidden)
        try backend.saveBackup(backup)
        #expect(backend.loadBackup() == backup)

        backend.clearBackup()
        #expect(backend.loadBackup() == nil)
    }
}
