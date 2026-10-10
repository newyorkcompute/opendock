import Foundation
import ScriptedWidgetRuntime

/// `Examples/Widgets/hello`, found from this file's path as the docs tests find `docs/`.
enum SampleWidget {
    static let repoURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // ScriptedWidgetTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
    static let directory = repoURL.appendingPathComponent("Examples/Widgets/hello", isDirectory: true)
    static let manifestURL = directory.appendingPathComponent(ScriptedWidgetPackage.manifestFileName)

    /// A fresh temporary folder with a package in it, made from `manifest` and `script`.
    static func makePackage(
        named folder: String = "test", manifest: String, script: String, in root: URL? = nil
    ) throws -> URL {
        let root = try root ?? makeTemporaryDirectory()
        let directory = root.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(manifest.utf8).write(to: directory.appendingPathComponent(ScriptedWidgetPackage.manifestFileName))
        try Data(script.utf8).write(to: directory.appendingPathComponent("main.js"))
        return directory
    }

    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScriptedWidgetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A minimal valid manifest with `id`.
    static func manifest(
        id: String = "com.example.test", settings: String = "[]", permissions: String = "{}"
    ) -> String {
        """
        {"apiVersion": 1, "id": "\(id)", "name": "Test", "version": "1.0", "summary": "A test.", \
        "settings": \(settings), "permissions": \(permissions)}
        """
    }
}
