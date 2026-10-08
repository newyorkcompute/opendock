import Foundation
import Observation
import os

/// The single source of truth for the running app. Owns the document, persists
/// changes with a short debounce, and exposes convenience mutations.
///
/// Everything here is main-actor: views observe it directly.
@MainActor
@Observable
public final class DockStore {
    public private(set) var document: DockDocument
    public private(set) var lastError: (any Error)?

    @ObservationIgnored private let storage: DockStorage
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let saveDelay: Duration
    @ObservationIgnored private let log = Logger(subsystem: "com.newyorkcompute.opendock", category: "DockStore")

    public init(storage: DockStorage, document: DockDocument, saveDelay: Duration = .milliseconds(250)) {
        self.storage = storage
        self.document = document
        self.saveDelay = saveDelay
    }

    /// Loads from disk, or seeds a first-run document (and persists it) if nothing is there
    /// or the file is unreadable. Only a missing file counts as a fresh install that gets
    /// the welcome window; someone whose file was unreadable has used OpenDock before.
    public static func load(from storage: DockStorage = .default()) -> DockStore {
        var document = DockDocument.firstRun()
        if storage.exists {
            do {
                let saved = try storage.load()
                return DockStore(storage: storage, document: saved)
            } catch {
                Logger(subsystem: "com.newyorkcompute.opendock", category: "DockStore")
                    .error(
                        "Failed to read \(storage.fileURL.path): \(error.localizedDescription). Backing up and starting fresh."
                    )
                storage.backupCorruptFile()
            }
        } else {
            document.hasSeenWelcome = false
        }
        let store = DockStore(storage: storage, document: document)
        store.saveNow()
        return store
    }

    // MARK: - Reading

    public var profile: DockProfile { document.activeProfile }
    public var items: [DockItem] { document.activeProfile.items }
    public var settings: DockSettings { document.settings }

    // MARK: - Mutations

    /// All writes funnel through here so saving is in one place.
    public func update(_ body: (inout DockDocument) -> Void) {
        body(&document)
        scheduleSave()
    }

    public func updateProfile(_ body: (inout DockProfile) -> Void) {
        update { body(&$0.activeProfile) }
    }

    public func updateSettings(_ body: (inout DockSettings) -> Void) {
        update { body(&$0.settings) }
    }

    public func append(_ item: DockItem) {
        updateProfile { $0.append(item) }
    }

    public func insert(_ item: DockItem, at index: Int) {
        updateProfile { $0.insert(item, at: index) }
    }

    public func remove(id: DockItem.ID) {
        updateProfile { $0.remove(id: id) }
    }

    public func move(id: DockItem.ID, to destination: Int) {
        updateProfile { $0.move(id: id, to: destination) }
    }

    public func move(id: DockItem.ID, before targetID: DockItem.ID) {
        updateProfile { $0.move(id: id, before: targetID) }
    }

    public func updateItem(_ item: DockItem) {
        updateProfile { $0.update(item) }
    }

    /// Adds an app unless it is already pinned. Returns whether anything changed.
    @discardableResult
    public func addApp(at url: URL) -> Bool {
        guard !profile.containsApp(at: url) else { return false }
        append(.app(at: url))
        return true
    }

    @discardableResult
    public func addFolder(at url: URL) -> Bool {
        guard !profile.containsFolder(at: url) else { return false }
        append(.folder(at: url))
        return true
    }

    /// Swaps the active profile's apps for `urls`, leaving its other items in place.
    public func replaceApps(with urls: [URL]) {
        updateProfile { $0.replaceApps(with: urls) }
    }

    // MARK: - Recent apps

    public var recentApps: RecentApps { document.recentApps }

    /// `app` was just used: it becomes the most recent app. Nothing is written if it
    /// already was.
    public func recordRecentApp(
        _ app: AppItem, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) {
        var recents = document.recentApps
        guard recents.record(app, exists: exists) else { return }
        update { $0.recentApps = recents }
    }

    /// Takes `app` out of the recent apps until it's used again.
    public func removeRecentApp(_ app: AppItem) {
        var recents = document.recentApps
        guard recents.remove(app) else { return }
        update { $0.recentApps = recents }
    }

    // MARK: - Welcome

    /// True until the welcome window has been closed once on a fresh install.
    public var needsWelcome: Bool { !document.hasSeenWelcome }

    public func markWelcomeSeen() {
        guard !document.hasSeenWelcome else { return }
        update { $0.hasSeenWelcome = true }
    }

    // MARK: - Profiles

    public var profiles: [DockProfile] { document.profiles }
    public var activeProfileID: DockProfile.ID { document.activeProfileID }

    public func selectProfile(_ id: DockProfile.ID) {
        guard id != document.activeProfileID, document.profile(id: id) != nil else { return }
        update { $0.activateProfile(id) }
    }

    /// Adds an empty profile at the end without activating it.
    @discardableResult
    public func addProfile(named name: String? = nil) -> DockProfile.ID {
        var id = document.activeProfileID
        update { id = $0.addProfile(named: name) }
        return id
    }

    /// Copies a profile, right after it, without activating the copy.
    @discardableResult
    public func duplicateProfile(_ id: DockProfile.ID) -> DockProfile.ID? {
        guard document.profile(id: id) != nil else { return nil }
        var copy: DockProfile.ID?
        update { copy = $0.duplicateProfile(id) }
        return copy
    }

    public func renameProfile(_ id: DockProfile.ID, to name: String) {
        guard let current = document.profile(id: id)?.name,
            current != name.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return }
        update { $0.renameProfile(id, to: name) }
    }

    /// Deletes a profile unless it's the last one left.
    @discardableResult
    public func deleteProfile(_ id: DockProfile.ID) -> Bool {
        guard document.profiles.count > 1, document.profile(id: id) != nil else { return false }
        var deleted = false
        update { deleted = $0.deleteProfile(id) }
        return deleted
    }

    public func moveProfile(_ id: DockProfile.ID, by offset: Int) {
        update { $0.moveProfile(id, by: offset) }
    }

    // MARK: - Focus modes

    /// Sets the profile a Focus mode shows, or none when `id` is nil.
    public func setFocusProfile(_ id: DockProfile.ID?, for mode: String) {
        guard document.settings.focusRules.profile(for: mode) != id else { return }
        updateSettings { $0.focusRules.setProfile(id, for: mode) }
    }

    /// Records that the active Focus changed to `mode` (nil when Focus turned off) and returns
    /// the profile the dock should switch to, if any. See `DockDocument.profileForFocusChange`.
    public func profileForFocusChange(to mode: String?) -> DockProfile.ID? {
        var changed = document
        let target = changed.profileForFocusChange(to: mode)
        if changed != document { update { $0 = changed } }
        return target
    }

    /// Keeps whether the welcome window was seen: that's about this install, not the layout.
    public func resetToFirstRun() {
        var fresh = DockDocument.firstRun()
        fresh.hasSeenWelcome = document.hasSeenWelcome
        update { $0 = fresh }
    }

    // MARK: - Export / import

    public func exportData() throws -> Data {
        try DockStorage.encode(document)
    }

    /// Like `resetToFirstRun`, keeps whether the welcome window was seen. The recent apps
    /// stay too: they're about what was used on this Mac, not part of a layout.
    public func importData(_ data: Data) throws {
        var imported = try DockStorage.decode(data)
        imported.hasSeenWelcome = document.hasSeenWelcome
        imported.recentApps = document.recentApps
        update { $0 = imported }
    }

    // MARK: - Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self, saveDelay] in
            try? await Task.sleep(for: saveDelay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Write immediately. Call on quit.
    public func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        do {
            try storage.save(document)
            lastError = nil
        } catch {
            lastError = error
            log.error("Save failed: \(error.localizedDescription)")
        }
    }
}

extension DockStorage {
    /// Moves an unreadable file aside as `dock.json.corrupt-<timestamp>` so the user's
    /// data is never silently destroyed.
    func backupCorruptFile() {
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let backup = fileURL.appendingPathExtension("corrupt-\(stamp)")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
    }
}
