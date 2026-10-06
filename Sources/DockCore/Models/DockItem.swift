import Foundation

/// A single slot in the dock. The dock is an ordered list of these.
public struct DockItem: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var kind: Kind

    public init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }

    public enum Kind: Hashable, Codable, Sendable {
        case app(AppItem)
        case folder(FolderItem)
        case spacer(SpacerItem)
        case widget(WidgetInstance)
        /// A thin vertical line between groups of items, like the Dock's separators.
        /// Persisted as `{"divider": {}}`.
        case divider
    }
}

// MARK: - Convenience constructors

public extension DockItem {
    static func app(at url: URL) -> DockItem {
        DockItem(kind: .app(AppItem(url: url)))
    }

    static func folder(at url: URL) -> DockItem {
        DockItem(kind: .folder(FolderItem(url: url)))
    }

    static func spacer(_ size: SpacerItem.Size = .regular) -> DockItem {
        DockItem(kind: .spacer(SpacerItem(size: size)))
    }

    static func widget(_ typeID: String, settings: [String: String] = [:]) -> DockItem {
        DockItem(kind: .widget(WidgetInstance(typeID: typeID, settings: settings)))
    }

    static func divider() -> DockItem {
        DockItem(kind: .divider)
    }
}

// MARK: - Accessors

public extension DockItem {
    var appItem: AppItem? {
        if case let .app(item) = kind { return item }
        return nil
    }

    var folderItem: FolderItem? {
        if case let .folder(item) = kind { return item }
        return nil
    }

    var spacerItem: SpacerItem? {
        if case let .spacer(item) = kind { return item }
        return nil
    }

    var widgetInstance: WidgetInstance? {
        if case let .widget(item) = kind { return item }
        return nil
    }

    var isWidget: Bool { widgetInstance != nil }
    var isSpacer: Bool { spacerItem != nil }
    var isDivider: Bool { kind == .divider }
}

/// An application bundle pinned to the dock.
public struct AppItem: Hashable, Codable, Sendable {
    /// Location of the `.app` bundle on disk.
    public var url: URL
    /// Cached bundle identifier, used to match running processes even if the bundle moves.
    public var bundleIdentifier: String?

    public init(url: URL, bundleIdentifier: String? = nil) {
        self.url = url.standardizedFileURL
        self.bundleIdentifier = bundleIdentifier ?? Bundle(url: url)?.bundleIdentifier
    }

    public var displayName: String {
        url.deletingPathExtension().lastPathComponent
    }
}

/// A folder (or file) pinned to the dock.
public struct FolderItem: Hashable, Codable, Sendable {
    public var url: URL
    /// Optional user-facing override. Defaults to the last path component.
    public var customName: String?

    public init(url: URL, customName: String? = nil) {
        self.url = url.standardizedFileURL
        self.customName = customName
    }

    public var displayName: String {
        customName ?? url.lastPathComponent
    }
}

/// Empty space used to group items visually.
public struct SpacerItem: Hashable, Codable, Sendable {
    public enum Size: String, Codable, Sendable, CaseIterable {
        case small
        case regular
    }

    public var size: Size

    public init(size: Size = .regular) {
        self.size = size
    }
}

/// A placed widget. `typeID` is resolved against the widget registry at runtime;
/// `settings` is an opaque bag each widget owns.
public struct WidgetInstance: Hashable, Codable, Sendable {
    public var typeID: String
    public var settings: [String: String]

    public init(typeID: String, settings: [String: String] = [:]) {
        self.typeID = typeID
        self.settings = settings
    }
}
