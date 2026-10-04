import Foundation

/// A named, ordered dock layout. The MVP exposes a single profile in the UI,
/// but the model supports several so profile switching is a UI-only addition later.
public struct DockProfile: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var items: [DockItem]

    public init(id: UUID = UUID(), name: String, items: [DockItem] = []) {
        self.id = id
        self.name = name
        self.items = items
    }
}

// MARK: - Mutations

public extension DockProfile {
    mutating func append(_ item: DockItem) {
        items.append(item)
    }

    mutating func insert(_ item: DockItem, at index: Int) {
        let clamped = min(max(index, 0), items.count)
        items.insert(item, at: clamped)
    }

    mutating func remove(id: DockItem.ID) {
        items.removeAll { $0.id == id }
    }

    /// Moves the item with `id` so that it ends up at `destination`
    /// (an index into the array *after* the item has been removed).
    mutating func move(id: DockItem.ID, to destination: Int) {
        guard let source = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: source)
        let clamped = min(max(destination, 0), items.count)
        items.insert(item, at: clamped)
    }

    /// Moves the item with `id` to sit at the position currently occupied by `targetID`.
    mutating func move(id: DockItem.ID, before targetID: DockItem.ID) {
        guard id != targetID,
              let source = items.firstIndex(where: { $0.id == id }),
              let target = items.firstIndex(where: { $0.id == targetID })
        else { return }
        let item = items.remove(at: source)
        let adjustedTarget = source < target ? target - 1 : target
        items.insert(item, at: adjustedTarget)
    }

    func item(id: DockItem.ID) -> DockItem? {
        items.first { $0.id == id }
    }

    mutating func update(_ item: DockItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }

    /// True if an app with this bundle URL is already pinned.
    func containsApp(at url: URL) -> Bool {
        let path = url.normalizedPath
        return items.contains { $0.appItem?.url.normalizedPath == path }
    }

    func containsFolder(at url: URL) -> Bool {
        let path = url.normalizedPath
        return items.contains { $0.folderItem?.url.normalizedPath == path }
    }
}

public extension URL {
    /// Path suitable for equality checks: standardized, symlinks left alone,
    /// no trailing slash. `URL ==` treats `/a/` and `/a` as different.
    var normalizedPath: String {
        let path = standardizedFileURL.path
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
