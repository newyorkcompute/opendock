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
    @ObservationIgnored private let log = Logger(subsystem: "org.opendock", category: "DockStore")

    public init(storage: DockStorage, document: DockDocument, saveDelay: Duration = .milliseconds(250)) {
        self.storage = storage
        self.document = document
        self.saveDelay = saveDelay
    }

    /// Loads from disk, or seeds a first-run document (and persists it) if nothing is there
    /// or the file is unreadable.
    public static func load(from storage: DockStorage = .default()) -> DockStore {
        if storage.exists {
            do {
                let document = try storage.load()
                return DockStore(storage: storage, document: document)
            } catch {
                Logger(subsystem: "org.opendock", category: "DockStore")
                    .error("Failed to read \(storage.fileURL.path): \(error.localizedDescription). Backing up and starting fresh.")
                storage.backupCorruptFile()
            }
        }
        let store = DockStore(storage: storage, document: .firstRun())
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

    public func resetToFirstRun() {
        update { $0 = .firstRun() }
    }

    // MARK: - Export / import

    public func exportData() throws -> Data {
        try DockStorage.encode(document)
    }

    public func importData(_ data: Data) throws {
        let imported = try DockStorage.decode(data)
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
