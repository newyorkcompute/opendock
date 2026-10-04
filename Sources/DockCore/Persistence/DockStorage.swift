import Foundation

/// Reads and writes a `DockDocument` as JSON. Pure I/O, no state.
public struct DockStorage: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `~/Library/Application Support/OpenDock/dock.json`
    public static func `default`(fileManager: FileManager = .default) -> DockStorage {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("OpenDock", isDirectory: true)
        return DockStorage(fileURL: dir.appendingPathComponent("dock.json"))
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    public func load() throws -> DockDocument {
        let data = try Data(contentsOf: fileURL)
        return try DockStorage.decode(data)
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

    public static func decode(_ data: Data) throws -> DockDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var document = try decoder.decode(DockDocument.self, from: data)
        document = try migrate(document)
        return document
    }

    /// Forward-migrate older documents. Currently a no-op beyond a version check.
    static func migrate(_ document: DockDocument) throws -> DockDocument {
        guard document.version <= DockDocument.currentVersion else {
            throw StorageError.newerThanSupported(document.version)
        }
        var migrated = document
        migrated.version = DockDocument.currentVersion
        return migrated
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
