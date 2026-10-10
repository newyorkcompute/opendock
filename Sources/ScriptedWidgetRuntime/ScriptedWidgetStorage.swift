import Foundation

/// One widget's persistent JavaScript state: a JSON object in a file beside the package
/// folder (`<id>.storage.json` in the Widgets directory), capped at
/// `ScriptedWidgetLimits.maxStorageBytes`. Shared by every tile of that package. A `set`
/// that would pass the cap throws and leaves the file as it was.
public final class ScriptedWidgetStorage: @unchecked Sendable {
    /// Longest key `set` accepts.
    public static let maxKeyLength = 128

    public let fileURL: URL
    public let limits: ScriptedWidgetLimits

    private let lock = NSLock()
    private var values: [String: ScriptedJSON]

    /// `Widgets/<id>.storage.json`, next to the package folder rather than inside it, so
    /// replacing the folder keeps the state.
    public static func fileURL(beside packageDirectory: URL, id: String) -> URL {
        packageDirectory.deletingLastPathComponent().appendingPathComponent("\(id).storage.json")
    }

    /// Reads the file, or starts empty when there is no file yet. A file that isn't a JSON
    /// object fails the load.
    public init(fileURL: URL, limits: ScriptedWidgetLimits = .default) throws(ScriptedWidgetError) {
        self.fileURL = fileURL
        self.limits = limits
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            values = [:]
            return
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw .storageUnreadable
        }
        guard data.count <= limits.maxStorageBytes, let json = ScriptedJSON.parse(data),
            case let .object(object) = json
        else { throw .storageUnreadable }
        values = object
    }

    /// The value stored at `key`, or nil when there isn't one.
    public func get(_ key: String) -> ScriptedJSON? {
        lock.withLock { values[key] }
    }

    /// The value as compact JSON, or nil when the key is missing. What `opendock.storage.get`
    /// parses.
    public func jsonString(for key: String) -> String? {
        guard let value = get(key) else { return nil }
        return try? value.encodedString()
    }

    /// Stores `value`, or removes the key when `value` is nil. Throws without writing when the
    /// document would pass the cap or the key isn't one we accept.
    public func set(_ key: String, value: ScriptedJSON?) throws(ScriptedWidgetError) {
        if value != nil {
            guard Self.isValidKey(key) else {
                throw .invalidSetting(key: key, detail: "storage keys have to be 1 to \(Self.maxKeyLength) characters.")
            }
        }
        lock.lock()
        defer { lock.unlock() }
        var next = values
        if let value {
            next[key] = value
        } else {
            next.removeValue(forKey: key)
        }
        let data = try Self.encode(next)
        guard data.count <= limits.maxStorageBytes else {
            throw .storageTooLarge(bytes: data.count, limit: limits.maxStorageBytes)
        }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw .storageUnreadable
        }
        values = next
    }

    public static func isValidKey(_ key: String) -> Bool {
        !key.isEmpty && key.count <= maxKeyLength && !key.contains("\0")
    }

    /// Compact JSON object, keys sorted.
    public static func encode(_ values: [String: ScriptedJSON]) throws(ScriptedWidgetError) -> Data {
        do {
            return try ScriptedJSON.object(values).encoded()
        } catch let error as ScriptedWidgetError {
            throw error
        } catch {
            throw .storageUnreadable
        }
    }
}
