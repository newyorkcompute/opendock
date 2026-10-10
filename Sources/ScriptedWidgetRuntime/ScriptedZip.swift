import Foundation

/// One file in a zip archive, read from the central directory before anything is extracted.
public struct ScriptedZipEntry: Equatable, Sendable {
    public var name: String
    /// 0 is stored, 8 is deflated.
    public var method: Int
    public var compressedSize: Int
    public var uncompressedSize: Int
    public var localHeaderOffset: Int
    public var isDirectory: Bool
    /// Unix symlink, from the external attributes. Never extracted.
    public var isSymlink: Bool
}

/// Reads a zip's central directory and extracts stored entries. Names are checked before any
/// byte is written, so a `../` entry can't land outside the destination. Deflated entries are
/// left for the installer to hand to `ditto` after the same check.
public enum ScriptedZip {
    private static let localSignature = 0x0403_4B50
    private static let centralSignature = 0x0201_4B50
    private static let endSignature = 0x0605_4B50
    private static let stored = 0
    private static let deflated = 8
    private static let symlinkMode = 0o120_000

    /// The central directory. Throws when the archive is truncated, encrypted, Zip64, or
    /// uses a compression method other than stored or deflated.
    public static func entries(in data: Data) throws(ScriptedWidgetError) -> [ScriptedZipEntry] {
        guard let end = endOfCentralDirectory(in: data) else {
            throw .installFailed("This isn't a zip archive.")
        }
        let count = integer(data, end + 10, width: 2)
        let size = integer(data, end + 12, width: 4)
        let offset = integer(data, end + 16, width: 4)
        guard offset >= 0, size >= 0, offset <= data.count, size <= data.count - offset else {
            throw .installFailed("The archive's directory is incomplete.")
        }
        var cursor = offset
        let endOfDirectory = offset + size
        var entries: [ScriptedZipEntry] = []
        entries.reserveCapacity(count)
        for _ in 0 ..< count {
            guard cursor + 46 <= endOfDirectory, integer(data, cursor, width: 4) == centralSignature else {
                throw .installFailed("The archive's directory is incomplete.")
            }
            let flags = integer(data, cursor + 8, width: 2)
            if flags & 0x1 != 0 { throw .installFailed("Encrypted archives aren't supported.") }
            let method = integer(data, cursor + 10, width: 2)
            guard method == stored || method == deflated else {
                throw .installFailed("The archive uses a compression OpenDock can't read.")
            }
            let compressed = integer(data, cursor + 20, width: 4)
            let uncompressed = integer(data, cursor + 24, width: 4)
            if compressed == 0xFFFF_FFFF || uncompressed == 0xFFFF_FFFF {
                throw .installFailed("Zip64 archives aren't supported.")
            }
            let nameLength = integer(data, cursor + 28, width: 2)
            let extraLength = integer(data, cursor + 30, width: 2)
            let commentLength = integer(data, cursor + 32, width: 2)
            let attributes = integer(data, cursor + 38, width: 4)
            let localOffset = integer(data, cursor + 42, width: 4)
            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLength
            guard nameEnd <= endOfDirectory else { throw .installFailed("The archive's directory is incomplete.") }
            guard let name = String(data: data.subdata(in: nameStart ..< nameEnd), encoding: .utf8) else {
                throw .installFailed("An archive entry's name isn't UTF-8.")
            }
            let mode = (attributes >> 16) & 0xFFFF
            entries.append(
                ScriptedZipEntry(
                    name: name, method: method, compressedSize: compressed, uncompressedSize: uncompressed,
                    localHeaderOffset: localOffset, isDirectory: name.hasSuffix("/"),
                    isSymlink: mode & 0o170_000 == symlinkMode))
            cursor = nameEnd + extraLength + commentLength
            guard cursor <= endOfDirectory else { throw .installFailed("The archive's directory is incomplete.") }
        }
        return entries
    }

    /// Refuses escaped names, symlinks, and archives over the package cap. Call this before
    /// extracting.
    public static func validate(_ entries: [ScriptedZipEntry], limits: ScriptedWidgetLimits) throws(ScriptedWidgetError)
    {
        var total = 0
        var seen: Set<String> = []
        for entry in entries {
            if let reason = rejection(of: entry.name) { throw .installFailed(reason) }
            if entry.isSymlink { throw .installFailed("The archive contains a symlink, \(entry.name).") }
            if !seen.insert(entry.name).inserted {
                throw .installFailed("The archive lists \(entry.name) more than once.")
            }
            total += entry.uncompressedSize
            if total > limits.maxPackageBytes {
                throw .installFailed(
                    "The archive is \(total) bytes; the most a widget may be is \(limits.maxPackageBytes).")
            }
        }
    }

    /// Why `name` may not be extracted, or nil when it's a relative path inside the archive.
    public static func rejection(of name: String) -> String? {
        if name.isEmpty { return "The archive contains an empty path." }
        if name.contains("\\") || name.contains("\0") || name.contains(":") {
            return "The archive contains a path that isn't allowed: \(name)."
        }
        if name.hasPrefix("/") { return "The archive contains an absolute path: \(name)." }
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        let meaningful = parts.dropLast(parts.last?.isEmpty == true ? 1 : 0)
        if meaningful.isEmpty || meaningful.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) {
            return "The archive contains a path that escapes the widget: \(name)."
        }
        return nil
    }

    /// Writes stored entries into `directory`, which the caller created. A deflated entry throws.
    public static func extractStored(
        _ data: Data, entries: [ScriptedZipEntry], to directory: URL, fileManager: FileManager = .default
    ) throws(ScriptedWidgetError) {
        for entry in entries where !entry.isDirectory {
            guard entry.method == stored else {
                throw .installFailed("The archive is compressed.")
            }
            guard entry.compressedSize == entry.uncompressedSize else {
                throw .installFailed("The archive's sizes don't match for \(entry.name).")
            }
            let start = try dataOffset(of: entry, in: data)
            let end = start + entry.compressedSize
            guard end <= data.count else { throw .installFailed("The archive is incomplete.") }
            let url = try destination(entry.name, in: directory)
            let folder = url.deletingLastPathComponent()
            do {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.subdata(in: start ..< end).write(to: url, options: .atomic)
            } catch let error as ScriptedWidgetError {
                throw error
            } catch {
                throw .installFailed("Couldn't write \(entry.name).")
            }
        }
    }

    /// A path inside `directory` for a name `validate` already accepted.
    static func destination(_ name: String, in directory: URL) throws(ScriptedWidgetError) -> URL {
        let relative = name.hasSuffix("/") ? String(name.dropLast()) : name
        let url = relative.split(separator: "/").reduce(directory) { $0.appendingPathComponent(String($1)) }
        guard ScriptedWidgetPackage.contains(url, in: directory) else {
            throw .installFailed("The archive contains a path that escapes the widget: \(name).")
        }
        return url
    }

    private static func dataOffset(of entry: ScriptedZipEntry, in data: Data) throws(ScriptedWidgetError) -> Int {
        let offset = entry.localHeaderOffset
        guard offset >= 0, offset + 30 <= data.count, integer(data, offset, width: 4) == localSignature else {
            throw .installFailed("The archive is incomplete.")
        }
        let nameLength = integer(data, offset + 26, width: 2)
        let extraLength = integer(data, offset + 28, width: 2)
        let start = offset + 30 + nameLength + extraLength
        guard start <= data.count else { throw .installFailed("The archive is incomplete.") }
        return start
    }

    /// Offset of the end-of-central-directory record, searching back from the end of the file.
    private static func endOfCentralDirectory(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let lower = max(0, data.count - (65_535 + 22))
        var index = data.count - 22
        while index >= lower {
            if integer(data, index, width: 4) == endSignature {
                let comment = integer(data, index + 20, width: 2)
                if index + 22 + comment == data.count { return index }
            }
            if index == 0 { break }
            index -= 1
        }
        return nil
    }

    private static func integer(_ data: Data, _ offset: Int, width: Int) -> Int {
        guard offset >= 0, width > 0, offset + width <= data.count else { return -1 }
        var value = 0
        for shift in 0 ..< width {
            value |= Int(data[offset + shift]) << (8 * shift)
        }
        return value
    }
}
