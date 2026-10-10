import Foundation

/// What Settings shows before copying a widget in: its name, what it may do, and whether an
/// installed copy of the same id will be replaced. The source is the folder or zip the user
/// picked; nothing has been copied yet.
public struct ScriptedInstallInspection: Equatable, Sendable, Identifiable {
    public var source: URL
    public var manifest: ScriptedWidgetManifest
    /// True when the Widgets folder already has this id. Replacing keeps the storage file.
    public var replacesExisting: Bool

    public var id: String { source.path }
}

/// Copies a scripted widget folder, or a zip of one, into the Widgets directory under the
/// manifest's id. A zip is checked for escaping paths before it is extracted. Replacing a
/// widget removes the old folder and leaves `Widgets/<id>.storage.json` alone.
public enum ScriptedWidgetInstaller {
    /// Reads the manifest and says whether this id is already installed. Does not copy.
    public static func inspect(
        _ url: URL, into widgetsDirectory: URL, limits: ScriptedWidgetLimits = .default
    ) throws(ScriptedWidgetError) -> ScriptedInstallInspection {
        let staged = try stage(url, limits: limits)
        defer { staged.cleanup() }
        let existing = ScriptedWidgetPackage.scan(widgetsDirectory).packages.contains { $0.id == staged.package.id }
        return ScriptedInstallInspection(
            source: url, manifest: staged.package.manifest, replacesExisting: existing)
    }

    /// Copies `url` (a folder, or a `.zip` of a folder or of its contents) into
    /// `widgetsDirectory`, named by the manifest id. An older folder with the same id is removed.
    public static func install(
        from url: URL, into widgetsDirectory: URL, limits: ScriptedWidgetLimits = .default,
        fileManager: FileManager = .default
    ) throws(ScriptedWidgetError) -> ScriptedWidgetPackage {
        let staged = try stage(url, limits: limits, fileManager: fileManager)
        defer { staged.cleanup() }
        let id = staged.package.id
        let destination = widgetsDirectory.appendingPathComponent(id, isDirectory: true)
        if staged.root.resolvingSymlinksInPath().standardizedFileURL.path
            == destination.resolvingSymlinksInPath().standardizedFileURL.path
        {
            return try ScriptedWidgetPackage.load(from: destination, limits: limits)
        }
        do {
            try fileManager.createDirectory(at: widgetsDirectory, withIntermediateDirectories: true)
        } catch {
            throw .installFailed("Couldn't create the Widgets folder.")
        }
        let staging = widgetsDirectory.appendingPathComponent(".\(id).installing", isDirectory: true)
        if fileManager.fileExists(atPath: staging.path) {
            try removeDirectory(staging, from: widgetsDirectory, fileManager: fileManager)
        }
        do {
            try fileManager.copyItem(at: staged.root, to: staging)
        } catch {
            throw .installFailed("Couldn't copy the widget into the Widgets folder.")
        }
        let siblings = ScriptedWidgetPackage.scan(widgetsDirectory, fileManager: fileManager).packages.filter {
            $0.id == id
        }
        do {
            for sibling in siblings {
                try removeDirectory(sibling.directory, from: widgetsDirectory, fileManager: fileManager)
            }
            if fileManager.fileExists(atPath: destination.path) {
                try removeDirectory(destination, from: widgetsDirectory, fileManager: fileManager)
            }
            try fileManager.moveItem(at: staging, to: destination)
        } catch let error as ScriptedWidgetError {
            try? fileManager.removeItem(at: staging)
            throw error
        } catch {
            try? fileManager.removeItem(at: staging)
            throw .installFailed("Couldn't copy the widget into the Widgets folder.")
        }
        return try ScriptedWidgetPackage.load(from: destination, limits: limits)
    }

    /// Deletes the package folder and its `Widgets/<id>.storage.json`. Both have to sit in
    /// `widgetsDirectory`.
    public static func remove(
        _ packageDirectory: URL, id: String, from widgetsDirectory: URL, fileManager: FileManager = .default
    ) throws(ScriptedWidgetError) {
        try removeDirectory(packageDirectory, from: widgetsDirectory, fileManager: fileManager)
        let storage = ScriptedWidgetStorage.fileURL(beside: widgetsDirectory.appendingPathComponent(id), id: id)
        let storageIsInside = ScriptedWidgetPackage.contains(storage, in: widgetsDirectory)
        guard storageIsInside || !fileManager.fileExists(atPath: storage.path) else {
            throw .installFailed("The widget's saved state isn't in the Widgets folder.")
        }
        guard fileManager.fileExists(atPath: storage.path) else { return }
        do {
            try fileManager.removeItem(at: storage)
        } catch {
            throw .installFailed("Couldn't remove the widget's saved state.")
        }
    }

    /// Extracts or locates the package in a temporary place when it came from a zip.
    private static func stage(
        _ url: URL, limits: ScriptedWidgetLimits, fileManager: FileManager = .default
    ) throws(ScriptedWidgetError) -> Staged {
        let isDirectory =
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        if isDirectory {
            let root = try packageRoot(in: url, fileManager: fileManager)
            try enforcePackageSize(of: root, limits: limits, fileManager: fileManager)
            let package = try ScriptedWidgetPackage.load(from: root, limits: limits)
            return Staged(root: root, temporary: nil, package: package)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .installFailed("Couldn't read \(url.lastPathComponent).")
        }
        guard data.count <= limits.maxPackageBytes else {
            throw .installFailed(
                "The archive is \(data.count) bytes; the most a widget may be is \(limits.maxPackageBytes).")
        }
        let entries = try ScriptedZip.entries(in: data)
        try ScriptedZip.validate(entries, limits: limits)
        let temporary = fileManager.temporaryDirectory.appendingPathComponent(
            "opendock-widget-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
        } catch {
            throw .installFailed("Couldn't prepare a folder for the archive.")
        }
        let extracted = temporary.appendingPathComponent("contents", isDirectory: true)
        do {
            try fileManager.createDirectory(at: extracted, withIntermediateDirectories: true)
            if entries.contains(where: { !$0.isDirectory && $0.method != 0 }) {
                try extractDeflated(url, to: extracted, fileManager: fileManager)
            } else {
                try ScriptedZip.extractStored(data, entries: entries, to: extracted, fileManager: fileManager)
            }
        } catch let error as ScriptedWidgetError {
            try? fileManager.removeItem(at: temporary)
            throw error
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw .installFailed("Couldn't extract the archive.")
        }
        do {
            let root = try packageRoot(in: extracted, fileManager: fileManager)
            try enforcePackageSize(of: root, limits: limits, fileManager: fileManager)
            let package = try ScriptedWidgetPackage.load(from: root, limits: limits)
            return Staged(root: root, temporary: temporary, package: package)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    /// `directory` itself when it has a manifest, or its one child folder when the zip wrapped
    /// the package in a folder. `__MACOSX` is ignored.
    private static func packageRoot(in directory: URL, fileManager: FileManager) throws(ScriptedWidgetError) -> URL {
        let manifest = directory.appendingPathComponent(ScriptedWidgetPackage.manifestFileName)
        if fileManager.fileExists(atPath: manifest.path) { return directory }
        let children =
            (try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        let meaningful = children.filter { $0.lastPathComponent != "__MACOSX" }
        guard meaningful.count == 1, let only = meaningful.first,
            (try? only.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
            fileManager.fileExists(atPath: only.appendingPathComponent(ScriptedWidgetPackage.manifestFileName).path)
        else {
            throw .installFailed("The widget needs a manifest.json, or one folder that has one.")
        }
        return only
    }

    private static func enforcePackageSize(
        of root: URL, limits: ScriptedWidgetLimits, fileManager: FileManager
    ) throws(ScriptedWidgetError) {
        guard
            let enumerator = fileManager.enumerator(
                at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles])
        else { return }
        var total = 0
        for case let item as URL in enumerator {
            let values = try? item.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            total += values?.fileSize ?? 0
            if total > limits.maxPackageBytes {
                throw .installFailed(
                    "The widget is \(total) bytes; the most allowed is \(limits.maxPackageBytes).")
            }
        }
    }

    private static func extractDeflated(
        _ archive: URL, to directory: URL, fileManager: FileManager
    ) throws(ScriptedWidgetError) {
        #if os(macOS)
            guard fileManager.isExecutableFile(atPath: "/usr/bin/ditto") else {
                throw .installFailed("This archive is compressed, and this system can't extract it.")
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", archive.path, directory.path]
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                throw .installFailed("Couldn't extract the archive.")
            }
            guard process.terminationStatus == 0 else { throw .installFailed("Couldn't extract the archive.") }
        #else
            throw .installFailed("This archive is compressed, and this system can't extract it.")
        #endif
    }

    private static func removeDirectory(
        _ directory: URL, from widgetsDirectory: URL, fileManager: FileManager
    ) throws(ScriptedWidgetError) {
        let directoryPath = directory.resolvingSymlinksInPath().standardizedFileURL.path
        let widgetsPath = widgetsDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        guard directoryPath != widgetsPath, ScriptedWidgetPackage.contains(directory, in: widgetsDirectory) else {
            throw .installFailed("That widget isn't in the Widgets folder.")
        }
        do {
            try fileManager.removeItem(at: directory)
        } catch {
            throw .installFailed("Couldn't remove the widget.")
        }
    }

    /// A package located for inspection or install. `temporary` is deleted on cleanup; a folder
    /// the user already has is left alone.
    private struct Staged {
        var root: URL
        var temporary: URL?
        var package: ScriptedWidgetPackage

        func cleanup() {
            guard let temporary else { return }
            try? FileManager.default.removeItem(at: temporary)
        }
    }
}
