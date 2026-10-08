import Foundation

/// How a folder's contents are ordered when it's browsed from the dock.
public enum FolderSortOrder: String, Codable, Sendable, CaseIterable {
    /// By name, as Finder sorts names ("File 2" before "File 10").
    case name
    /// Newest first: handy for Downloads.
    case dateAdded
    /// Most recently changed first.
    case dateModified
    /// By kind ("Folder", "PDF document", ...), then by name.
    case kind

    public var title: String {
        switch self {
        case .name: "Name"
        case .dateAdded: "Date Added"
        case .dateModified: "Date Modified"
        case .kind: "Kind"
        }
    }
}

/// One item in a browsed folder.
public struct FolderEntry: Identifiable, Hashable, Sendable {
    public var url: URL
    /// The name Finder shows, which hides the extension when Finder is set to.
    public var name: String
    /// A folder that can be browsed into. Packages such as apps count as files.
    public var isFolder: Bool
    public var dateAdded: Date?
    public var dateModified: Date?
    public var kind: String?

    public init(
        url: URL,
        name: String? = nil,
        isFolder: Bool = false,
        dateAdded: Date? = nil,
        dateModified: Date? = nil,
        kind: String? = nil
    ) {
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.isFolder = isFolder
        self.dateAdded = dateAdded
        self.dateModified = dateModified
        self.kind = kind
    }

    public var id: String { url.normalizedPath }
}

/// What's in a folder, sorted, and cut off at a limit so a huge folder stays quick to show.
public struct FolderContents: Hashable, Sendable {
    public var entries: [FolderEntry]
    /// How many visible items the folder has, including any past the limit.
    public var totalCount: Int

    public init(entries: [FolderEntry], totalCount: Int) {
        self.entries = entries
        self.totalCount = totalCount
    }

    public var isTruncated: Bool { totalCount > entries.count }
}

/// Lists and sorts folders for the dock's folder popover.
public enum FolderListing {
    /// Past this many items, the popover points to Finder for the rest.
    public static let defaultLimit = 500

    private static let resourceKeys: [URLResourceKey] = [
        .localizedNameKey, .isDirectoryKey, .isPackageKey, .addedToDirectoryDateKey,
        .contentModificationDateKey, .localizedTypeDescriptionKey,
    ]

    /// Whether `url` is a folder whose contents can be shown, rather than a file or a package.
    public static func isBrowsable(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]) else { return false }
        return values.isDirectory == true && values.isPackage != true
    }

    /// The visible items in `folder`, sorted by `order`, at most `limit` of them.
    /// Hidden files are skipped, as Finder skips them.
    public static func contents(
        of folder: URL,
        sortedBy order: FolderSortOrder,
        limit: Int = defaultLimit,
        fileManager: FileManager = .default
    ) throws -> FolderContents {
        let urls = try fileManager.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles])
        let entries = urls.map(entry(for:))
        return FolderContents(entries: Array(sorted(entries, by: order).prefix(max(limit, 0))), totalCount: urls.count)
    }

    public static func sorted(_ entries: [FolderEntry], by order: FolderSortOrder) -> [FolderEntry] {
        entries.sorted { areInIncreasingOrder($0, $1, by: order) }
    }

    static func areInIncreasingOrder(_ a: FolderEntry, _ b: FolderEntry, by order: FolderSortOrder) -> Bool {
        switch order {
        case .name:
            break
        case .dateAdded:
            if let result = newerFirst(a.dateAdded, b.dateAdded) { return result }
        case .dateModified:
            if let result = newerFirst(a.dateModified, b.dateModified) { return result }
        case .kind:
            let comparison = (a.kind ?? "").localizedStandardCompare(b.kind ?? "")
            if comparison != .orderedSame { return comparison == .orderedAscending }
        }
        let comparison = a.name.localizedStandardCompare(b.name)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return a.url.normalizedPath < b.url.normalizedPath
    }

    /// Nil when the dates don't decide the order. Items without a date go last.
    private static func newerFirst(_ a: Date?, _ b: Date?) -> Bool? {
        switch (a, b) {
        case let (a?, b?): a == b ? nil : a > b
        case (_?, nil): true
        case (nil, _?): false
        case (nil, nil): nil
        }
    }

    private static func entry(for url: URL) -> FolderEntry {
        let values = try? url.resourceValues(forKeys: Set(resourceKeys))
        return FolderEntry(
            url: url,
            name: values?.localizedName,
            isFolder: values?.isDirectory == true && values?.isPackage != true,
            dateAdded: values?.addedToDirectoryDate,
            dateModified: values?.contentModificationDate,
            kind: values?.localizedTypeDescription
        )
    }
}
