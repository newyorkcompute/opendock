import DockCore
import Foundation
import os

/// The two `com.apple.dock` preferences OpenDock changes to hide Apple's Dock.
/// `nil` means the key isn't set, so the Dock uses its built-in default.
public struct AppleDockPreferences: Hashable, Codable, Sendable {
    /// `autohide`: the "Automatically hide and show the Dock" setting.
    public var autohide: Bool?
    /// `autohide-delay`: seconds the pointer must rest at the screen edge before the Dock reveals.
    public var autohideDelay: Double?

    public init(autohide: Bool? = nil, autohideDelay: Double? = nil) {
        self.autohide = autohide
        self.autohideDelay = autohideDelay
    }

    /// Auto-hide with a reveal delay long enough that the Dock never comes back on its own.
    public static let hidden = AppleDockPreferences(autohide: true, autohideDelay: 1000)
}

/// What `AppleDockHider` persists before it touches Apple's Dock, so the user's
/// settings can be put back even if OpenDock is killed before it can restore them.
public struct AppleDockBackup: Hashable, Codable, Sendable {
    /// The user's preferences before OpenDock changed them.
    public var original: AppleDockPreferences
    /// What OpenDock wrote. A value that no longer matches was changed by the user.
    public var applied: AppleDockPreferences

    public init(original: AppleDockPreferences, applied: AppleDockPreferences) {
        self.original = original
        self.applied = applied
    }
}

/// Everything `AppleDockHider` touches outside the process.
@MainActor
public protocol AppleDockBackend: AnyObject {
    func readDockPreferences() -> AppleDockPreferences
    /// Writes `preferences` to disk; `nil` values remove the key.
    func writeDockPreferences(_ preferences: AppleDockPreferences)
    /// Relaunches Apple's Dock so it picks up the written preferences.
    func restartDock()

    func loadBackup() -> AppleDockBackup?
    /// Must be durable once this returns: OpenDock may be killed right after.
    func saveBackup(_ backup: AppleDockBackup) throws
    func clearBackup()
}

/// Hides Apple's Dock while OpenDock runs and puts the user's Dock settings back afterwards.
///
/// Hiding sets `com.apple.dock` `autohide` and a very long `autohide-delay`, then restarts
/// the Dock. Before writing, the user's values are saved in a backup that outlives the
/// process. Restoring writes them back and deletes the backup. It runs when the option is
/// turned off, when OpenDock quits, and on the next launch if a previous run was killed
/// before it could restore. A value the user changed while OpenDock was running is kept.
@MainActor
public final class AppleDockHider {
    private let backend: any AppleDockBackend
    private let log = Logger(subsystem: "com.newyorkcompute.opendock", category: "AppleDockHider")

    public init(backend: any AppleDockBackend) {
        self.backend = backend
    }

    /// Hides Apple's Dock when `hide` is true, otherwise restores the user's settings.
    /// Safe to call repeatedly. At launch, a leftover backup is either restored or, when
    /// `hide` is true, kept so the original values still go back at quit.
    public func apply(hide: Bool) {
        if hide { self.hide() } else { restore() }
    }

    public func hide() {
        let current = backend.readDockPreferences()
        let target = AppleDockPreferences.hidden
        if backend.loadBackup() == nil {
            var original = current
            // The hidden delay means an earlier backup was lost; never restore it.
            if original.autohideDelay == target.autohideDelay { original.autohideDelay = nil }
            do {
                try backend.saveBackup(AppleDockBackup(original: original, applied: target))
            } catch {
                log.error("Not hiding Apple's Dock: couldn't save its settings: \(error.localizedDescription)")
                return
            }
        }
        guard current != target else { return }
        backend.writeDockPreferences(target)
        backend.restartDock()
        log.info("Hid Apple's Dock")
    }

    public func restore() {
        guard let backup = backend.loadBackup() else { return }
        let current = backend.readDockPreferences()
        var restored = current
        if current.autohide == backup.applied.autohide { restored.autohide = backup.original.autohide }
        if current.autohideDelay == backup.applied.autohideDelay {
            restored.autohideDelay = backup.original.autohideDelay
        }
        if restored != current {
            backend.writeDockPreferences(restored)
            backend.restartDock()
        }
        backend.clearBackup()
        log.info("Restored Apple's Dock settings")
    }
}

// MARK: - System backend

/// Reads and writes `com.apple.dock` through CFPreferences, the same store `defaults` uses,
/// and keeps the backup as a small JSON file next to `dock.json`.
@MainActor
public final class SystemAppleDockBackend: AppleDockBackend {
    private static let domain = "com.apple.dock" as CFString
    private static let autohideKey = "autohide" as CFString
    private static let autohideDelayKey = "autohide-delay" as CFString

    private let backupURL: URL
    private let log = Logger(subsystem: "com.newyorkcompute.opendock", category: "AppleDockHider")

    /// `~/Library/Application Support/OpenDock/apple-dock-backup.json` by default.
    public init(
        backupURL: URL = DockStorage.default().fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("apple-dock-backup.json")
    ) {
        self.backupURL = backupURL
    }

    public func readDockPreferences() -> AppleDockPreferences {
        CFPreferencesAppSynchronize(Self.domain)
        return AppleDockPreferences(
            autohide: CFPreferencesCopyAppValue(Self.autohideKey, Self.domain) as? Bool,
            autohideDelay: CFPreferencesCopyAppValue(Self.autohideDelayKey, Self.domain) as? Double
        )
    }

    public func writeDockPreferences(_ preferences: AppleDockPreferences) {
        CFPreferencesSetAppValue(Self.autohideKey, preferences.autohide.map { NSNumber(value: $0) }, Self.domain)
        CFPreferencesSetAppValue(
            Self.autohideDelayKey, preferences.autohideDelay.map { NSNumber(value: $0) }, Self.domain)
        if !CFPreferencesAppSynchronize(Self.domain) {
            log.error("Couldn't write Apple's Dock settings")
        }
    }

    public func restartDock() {
        let killall = Process()
        killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killall.arguments = ["Dock"]
        do {
            try killall.run()
        } catch {
            log.error("Couldn't restart Apple's Dock: \(error.localizedDescription)")
        }
    }

    public func loadBackup() -> AppleDockBackup? {
        guard let data = try? Data(contentsOf: backupURL) else { return nil }
        do {
            return try JSONDecoder().decode(AppleDockBackup.self, from: data)
        } catch {
            log.error("Ignoring unreadable \(self.backupURL.path): \(error.localizedDescription)")
            return nil
        }
    }

    public func saveBackup(_ backup: AppleDockBackup) throws {
        try FileManager.default.createDirectory(
            at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(backup).write(to: backupURL, options: .atomic)
    }

    public func clearBackup() {
        try? FileManager.default.removeItem(at: backupURL)
    }
}
