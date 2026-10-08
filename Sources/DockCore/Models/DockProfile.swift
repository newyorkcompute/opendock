import Foundation

/// A named, ordered dock layout. A document holds one or more, and the dock shows the
/// active one. Settings (size, material, behavior) are shared by all profiles.
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

// MARK: - Tolerant decoding

extension DockProfile {
    /// Items this build can't decode (an item kind added by a newer version, say) are
    /// dropped one by one instead of failing the whole file, which would reset the dock.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        var decoded: [DockItem] = []
        if c.contains(.items) {
            var list = try c.nestedUnkeyedContainer(forKey: .items)
            while !list.isAtEnd {
                if let item = try? list.decode(DockItem.self) {
                    decoded.append(item)
                } else {
                    // A failed decode doesn't advance the container; step over the element.
                    _ = try list.decode(SkippedElement.self)
                }
            }
        }
        items = decoded
    }

    private struct SkippedElement: Decodable {
        init(from decoder: any Decoder) throws {}
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

    /// Index just after the item with `id`: where an item added "after" it goes. The end
    /// when `id` is nil or not in the profile.
    func index(after id: DockItem.ID?) -> Int {
        guard let id, let index = items.firstIndex(where: { $0.id == id }) else { return items.count }
        return index + 1
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

    /// Replaces every app with the apps at `urls`, in order and without duplicates. They go
    /// where the first app was, or at the start; every other item stays where it is.
    mutating func replaceApps(with urls: [URL]) {
        let index = items.firstIndex { $0.appItem != nil } ?? 0
        items.removeAll { $0.appItem != nil }
        var seen = Set<String>()
        let apps = urls.filter { seen.insert($0.normalizedPath).inserted }.map(DockItem.app(at:))
        items.insert(contentsOf: apps, at: index)
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
