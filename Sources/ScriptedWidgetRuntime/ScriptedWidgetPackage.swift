import Foundation

/// A scripted widget as installed: a folder with `manifest.json`, the script it names, and
/// whatever else the author put there. Loading reads both files once; `revision` changes when
/// either does on disk, so a tile knows to reload.
public struct ScriptedWidgetPackage: Equatable, Sendable, Identifiable {
    public static let manifestFileName = "manifest.json"

    public var id: String { manifest.id }
    public let directory: URL
    public let manifest: ScriptedWidgetManifest
    public let script: String
    public let revision: Revision

    /// When the manifest and the script were last written, and how big the script is. Equal
    /// revisions mean nothing worth reloading changed.
    public struct Revision: Hashable, Sendable {
        public var manifestModified: Date?
        public var scriptModified: Date?
        public var scriptSize: Int

        public init(manifestModified: Date?, scriptModified: Date?, scriptSize: Int) {
            self.manifestModified = manifestModified
            self.scriptModified = scriptModified
            self.scriptSize = scriptSize
        }
    }

    public init(directory: URL, manifest: ScriptedWidgetManifest, script: String, revision: Revision) {
        self.directory = directory
        self.manifest = manifest
        self.script = script
        self.revision = revision
    }

    /// Where the script is, for error messages and source URLs.
    public var scriptURL: URL {
        directory.appendingPathComponent(manifest.main)
    }

    /// `~/Library/Application Support/OpenDock/Widgets`, next to `dock.json`.
    public static func defaultDirectory(fileManager: FileManager = .default) -> URL {
        let base =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("OpenDock/Widgets", isDirectory: true)
    }

    /// Reads the package in `directory`: the manifest, then the script it names.
    public static func load(from directory: URL, limits: ScriptedWidgetLimits = .default) throws(ScriptedWidgetError)
        -> ScriptedWidgetPackage
    {
        let manifestURL = directory.appendingPathComponent(manifestFileName)
        let manifestData: Data
        do {
            manifestData = try Data(contentsOf: manifestURL)
        } catch {
            throw .unreadableFile(manifestFileName, reason: Self.reason(error))
        }
        let manifest = try ScriptedWidgetManifest.decode(manifestData)

        let scriptURL = directory.appendingPathComponent(manifest.main)
        let scriptData: Data
        do {
            scriptData = try Data(contentsOf: scriptURL)
        } catch {
            throw .unreadableFile(manifest.main, reason: Self.reason(error))
        }
        guard scriptData.count <= limits.maxScriptBytes else {
            throw .scriptTooLarge(bytes: scriptData.count, limit: limits.maxScriptBytes)
        }
        guard let script = String(data: scriptData, encoding: .utf8) else {
            throw .unreadableFile(manifest.main, reason: "not UTF-8 text")
        }
        let revision = Revision(
            manifestModified: modificationDate(of: manifestURL), scriptModified: modificationDate(of: scriptURL),
            scriptSize: scriptData.count)
        return ScriptedWidgetPackage(directory: directory, manifest: manifest, script: script, revision: revision)
    }

    /// Loads every package folder directly inside `directory`, in name order. Folders that
    /// aren't packages (no `manifest.json`) are skipped; ones that are but don't load, and later
    /// copies of an id already seen, are reported as problems.
    public static func scan(
        _ directory: URL, limits: ScriptedWidgetLimits = .default, fileManager: FileManager = .default
    )
        -> ScanResult
    {
        var result = ScanResult()
        guard
            let entries = try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else { return result }
        var seen: [String: URL] = [:]
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                fileManager.fileExists(atPath: entry.appendingPathComponent(manifestFileName).path)
            else { continue }
            do {
                let package = try load(from: entry, limits: limits)
                if let first = seen[package.id] {
                    result.problems.append(
                        Problem(
                            directory: entry,
                            message: "Another folder, \(first.lastPathComponent), already has the id \"\(package.id)\"."
                        ))
                } else {
                    seen[package.id] = entry
                    result.packages.append(package)
                }
            } catch {
                result.problems.append(Problem(directory: entry, message: error.description))
            }
        }
        return result
    }

    public struct ScanResult: Equatable, Sendable {
        public var packages: [ScriptedWidgetPackage] = []
        public var problems: [Problem] = []

        public init(packages: [ScriptedWidgetPackage] = [], problems: [Problem] = []) {
            self.packages = packages
            self.problems = problems
        }
    }

    /// A folder in the Widgets directory that looks like a package but didn't load.
    public struct Problem: Equatable, Sendable, Identifiable {
        public var id: URL { directory }
        public let directory: URL
        public let message: String

        public init(directory: URL, message: String) {
            self.directory = directory
            self.message = message
        }

        public var folderName: String { directory.lastPathComponent }
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private static func reason(_ error: any Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoSuchFileError {
            return "the file doesn't exist"
        }
        return nsError.localizedDescription
    }
}
