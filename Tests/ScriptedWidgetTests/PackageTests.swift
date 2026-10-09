import Foundation
import ScriptedWidgetRuntime
import Testing

@Suite("Scripted widget packages")
struct PackageTests {
    @Test func loadsTheHelloSample() throws {
        let package = try ScriptedWidgetPackage.load(from: SampleWidget.directory)
        #expect(package.id == "com.example.hello")
        #expect(package.manifest.name == "Hello")
        #expect(package.script.contains("function render("))
        #expect(package.scriptURL.lastPathComponent == "main.js")
        #expect(package.revision.scriptSize == package.script.utf8.count)
        #expect(package.revision.scriptModified != nil)
    }

    @Test func revisionFollowsTheFilesOnDisk() throws {
        let directory = try SampleWidget.makePackage(manifest: SampleWidget.manifest(), script: "function render() {}")
        let before = try ScriptedWidgetPackage.load(from: directory)
        #expect(before == (try ScriptedWidgetPackage.load(from: directory)))

        let scriptURL = directory.appendingPathComponent("main.js")
        try Data("function render() { return {}; }".utf8).write(to: scriptURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: scriptURL.path)
        let after = try ScriptedWidgetPackage.load(from: directory)
        #expect(after.revision != before.revision)
        #expect(after.script.contains("return {}"))
    }

    @Test func reportsWhatIsMissing() throws {
        let root = try SampleWidget.makeTemporaryDirectory()
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(throws: ScriptedWidgetError.unreadableFile("manifest.json", reason: "the file doesn't exist")) {
            try ScriptedWidgetPackage.load(from: empty)
        }

        let noScript = try SampleWidget.makePackage(
            named: "noscript", manifest: SampleWidget.manifest(), script: "", in: root)
        try FileManager.default.removeItem(at: noScript.appendingPathComponent("main.js"))
        #expect(throws: ScriptedWidgetError.unreadableFile("main.js", reason: "the file doesn't exist")) {
            try ScriptedWidgetPackage.load(from: noScript)
        }

        let badManifest = try SampleWidget.makePackage(
            named: "bad", manifest: "{\"apiVersion\": 1}", script: "", in: root)
        #expect(throws: ScriptedWidgetError.manifest(.missingField("id"))) {
            try ScriptedWidgetPackage.load(from: badManifest)
        }
    }

    @Test func refusesAScriptOverTheSizeLimit() throws {
        var limits = ScriptedWidgetLimits()
        limits.maxScriptBytes = 10
        let directory = try SampleWidget.makePackage(manifest: SampleWidget.manifest(), script: "function render() {}")
        #expect(throws: ScriptedWidgetError.scriptTooLarge(bytes: 20, limit: 10)) {
            try ScriptedWidgetPackage.load(from: directory, limits: limits)
        }
    }

    @Test func scansAFolderOfPackages() throws {
        let root = try SampleWidget.makeTemporaryDirectory()
        _ = try SampleWidget.makePackage(
            named: "b-second", manifest: SampleWidget.manifest(id: "com.example.b"), script: "", in: root)
        _ = try SampleWidget.makePackage(
            named: "a-first", manifest: SampleWidget.manifest(id: "com.example.a"), script: "", in: root)
        _ = try SampleWidget.makePackage(
            named: "c-duplicate", manifest: SampleWidget.manifest(id: "com.example.a"), script: "", in: root)
        _ = try SampleWidget.makePackage(named: "d-broken", manifest: "nope", script: "", in: root)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("not-a-widget"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("stray.txt"))
        try Data().write(to: root.appendingPathComponent(".DS_Store"))

        let result = ScriptedWidgetPackage.scan(root)
        #expect(result.packages.map(\.id) == ["com.example.a", "com.example.b"])
        #expect(result.packages.map(\.directory.lastPathComponent) == ["a-first", "b-second"])
        #expect(result.problems.map(\.folderName) == ["c-duplicate", "d-broken"])
        #expect(result.problems[0].message == "Another folder, a-first, already has the id \"com.example.a\".")
        #expect(result.problems[1].message.hasPrefix("manifest.json: couldn't be read"))
    }

    @Test func scanningAMissingFolderFindsNothing() {
        let result = ScriptedWidgetPackage.scan(URL(fileURLWithPath: "/nonexistent/OpenDock/Widgets"))
        #expect(result == ScriptedWidgetPackage.ScanResult())
    }

    @Test func defaultDirectoryIsNextToDockJSON() {
        let url = ScriptedWidgetPackage.defaultDirectory()
        #expect(url.pathComponents.suffix(2) == ["OpenDock", "Widgets"])
        #if os(macOS)
            #expect(url.pathComponents.suffix(3).first == "Application Support")
        #endif
    }
}
