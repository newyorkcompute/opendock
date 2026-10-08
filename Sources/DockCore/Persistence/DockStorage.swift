import Foundation

/// Reads and writes a `DockDocument` as JSON. Pure I/O, no state.
public struct DockStorage: Sendable {
    public let fileURL: URL
    /// Settings schemas by widget type ID. Widget settings in a loaded file are checked
    /// against them (see `DockDocument.sanitizeWidgetSettings(using:)`). Widgets without
    /// a schema here are left as they are.
    public let widgetSchemas: [String: WidgetSettingsSchema]

    public init(fileURL: URL, widgetSchemas: [String: WidgetSettingsSchema] = [:]) {
        self.fileURL = fileURL
        self.widgetSchemas = widgetSchemas
    }

    /// `~/Library/Application Support/OpenDock/dock.json`
    public static func `default`(
        fileManager: FileManager = .default, widgetSchemas: [String: WidgetSettingsSchema] = [:]
    ) -> DockStorage {
        let base =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("OpenDock", isDirectory: true)
        return DockStorage(fileURL: dir.appendingPathComponent("dock.json"), widgetSchemas: widgetSchemas)
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    public func load() throws -> DockDocument {
        let data = try Data(contentsOf: fileURL)
        return try DockStorage.decode(data, widgetSchemas: widgetSchemas)
    }

    public func save(_ document: DockDocument) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try DockStorage.encode(document)
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: Codec (shared by export/import)

    public static func encode(_ document: DockDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    /// Decodes and migrates a document, then replaces any widget setting that isn't valid
    /// for its key with the key's default. Unknown widgets and keys are kept untouched.
    public static func decode(_ data: Data, widgetSchemas: [String: WidgetSettingsSchema] = [:]) throws -> DockDocument
    {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var document = try decoder.decode(DockDocument.self, from: data)
        document = try migrate(document)
        document.sanitizeWidgetSettings(using: widgetSchemas)
        return document
    }

    /// Forward-migrate older documents, one version step at a time.
    static func migrate(_ document: DockDocument) throws -> DockDocument {
        guard document.version <= DockDocument.currentVersion else {
            throw StorageError.newerThanSupported(document.version)
        }
        var migrated = document
        if migrated.version < 2 {
            renameWidgetTypes(in: &migrated, prefix: legacyWidgetIDPrefix, to: widgetIDPrefix)
        }
        migrated.version = DockDocument.currentVersion
        return migrated
    }

    static let legacyWidgetIDPrefix = "org.opendock.widget."
    static let widgetIDPrefix = "com.newyorkcompute.opendock.widget."

    /// Rewrites every widget whose type ID starts with `oldPrefix`, in every profile,
    /// keeping its item ID, position, and settings.
    private static func renameWidgetTypes(
        in document: inout DockDocument, prefix oldPrefix: String, to newPrefix: String
    ) {
        document.updateWidgets { instance in
            guard instance.typeID.hasPrefix(oldPrefix) else { return }
            instance.typeID = newPrefix + String(instance.typeID.dropFirst(oldPrefix.count))
        }
    }

    public enum StorageError: Error, LocalizedError {
        case newerThanSupported(Int)

        public var errorDescription: String? {
            switch self {
            case let .newerThanSupported(version):
                "This file was saved by a newer version of OpenDock (format v\(version))."
            }
        }
    }
}
