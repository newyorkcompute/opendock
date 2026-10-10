import Foundation
import ScriptedWidgetRuntime
import Testing

@Suite("Scripted widget install")
struct InstallerTests {
    @Test func installsAFolderUnderTheManifestId() throws {
        let root = try SampleWidget.makeTemporaryDirectory()
        let source = try SampleWidget.makePackage(manifest: SampleWidget.manifest(), script: script, in: root)
        let widgets = root.appendingPathComponent("Widgets", isDirectory: true)
        let installed = try ScriptedWidgetInstaller.install(from: source, into: widgets)
        #expect(installed.id == "com.example.test")
        #expect(installed.directory.lastPathComponent == "com.example.test")
        #expect(FileManager.default.fileExists(atPath: installed.scriptURL.path))
    }

    @Test func inspectsAFolderWithoutCopyingIt() throws {
        let root = try SampleWidget.makeTemporaryDirectory()
        let source = try SampleWidget.makePackage(manifest: SampleWidget.manifest(), script: script, in: root)
        let widgets = root.appendingPathComponent("Widgets", isDirectory: true)
        let inspection = try ScriptedWidgetInstaller.inspect(source, into: widgets)
        #expect(inspection.manifest.name == "Test")
        #expect(!inspection.replacesExisting)
        #expect(!FileManager.default.fileExists(atPath: widgets.appendingPathComponent("com.example.test").path))
    }

    @Test func installsAZipOfThePackageContents() throws {
        let root = try SampleWidget.makeTemporaryDirectory()
        let widgets = root.appendingPathComponent("Widgets", isDirectory: true)
        let zip = root.appendingPathComponent("widget.zip")
        try StoredZip.archive([
            "manifest.json": Data(SampleWidget.manifest().utf8),
            "main.js": Data(script.utf8),
        ]).write(to: zip)
        let installed = try ScriptedWidgetInstaller.install(from: zip, into: widgets)
        #expect(installed.script == script)
    }

    @Test func installsAZipWrappedInOneFolder() throws {
        let root = try SampleWidget.makeTemporaryDirectory()
        let widgets = root.appendingPathComponent("Widgets", isDirectory: true)
        let zip = root.appendingPathComponent("widget.zip")
        try StoredZip.archive([
            "hello/manifest.json": Data(SampleWidget.manifest(id: "com.example.hello").utf8),
            "hello/main.js": Data(script.utf8),
        ]).write(to: zip)
        let installed = try ScriptedWidgetInstaller.install(from: zip, into: widgets)
        #expect(installed.directory.lastPathComponent == "com.example.hello")
        #expect(installed.script == script)
    }

    @Test func rejectsAZipThatEscapesBeforeWritingIt() throws {
        let root = try SampleWidget.makeTemporaryDirectory()
        let widgets = root.appendingPathComponent("Widgets", isDirectory: true)
        for name in ["../evil.txt", "hello/../../evil.txt", "/tmp/evil.txt", "..\\evil.txt"] {
            let zip = root.appendingPathComponent("widget.zip")
            try StoredZip.archive([
                name: Data("no".utf8),
                "manifest.json": Data(SampleWidget.manifest().utf8),
                "main.js": Data(script.utf8),
            ]).write(to: zip)
            #expect(throws: ScriptedWidgetError.self) {
                try ScriptedWidgetInstaller.install(from: zip, into: widgets)
            }
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("evil.txt").path))
        #expect(!FileManager.default.fileExists(atPath: widgets.appendingPathComponent("com.example.test").path))
    }

    @Test func rejectsAnArchiveOverTheCap() throws {
        var limits = ScriptedWidgetLimits()
        limits.maxPackageBytes = 16
        let root = try SampleWidget.makeTemporaryDirectory()
        let zip = root.appendingPathComponent("widget.zip")
        let archive = StoredZip.archive(["blob": Data(repeating: 1, count: 32)])
        try archive.write(to: zip)
        #expect(archive.count > limits.maxPackageBytes)
        #expect(
            throws: ScriptedWidgetError.installFailed(
                "The archive is \(archive.count) bytes; the most a widget may be is 16.")
        ) {
            try ScriptedWidgetInstaller.install(
                from: zip, into: root.appendingPathComponent("Widgets"), limits: limits)
        }
    }

    @Test func replacingKeepsTheStorageFileAndDropsTheOldFolder() throws {
        let root = try SampleWidget.makeTemporaryDirectory()
        let widgets = root.appendingPathComponent("Widgets", isDirectory: true)
        let first = try SampleWidget.makePackage(
            named: "old-name", manifest: SampleWidget.manifest(), script: script, in: root)
        try FileManager.default.createDirectory(at: widgets, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: first, to: widgets.appendingPathComponent("old-name"))
        let storageURL = ScriptedWidgetStorage.fileURL(
            beside: widgets.appendingPathComponent("com.example.test"), id: "com.example.test")
        let storage = try ScriptedWidgetStorage(fileURL: storageURL)
        try storage.set("count", value: .number(4))

        let replacement = "function render() { return { elements: [], refresh: 9 }; }"
        let second = try SampleWidget.makePackage(
            named: "newer", manifest: SampleWidget.manifest(), script: replacement, in: root)
        let installed = try ScriptedWidgetInstaller.install(from: second, into: widgets)
        #expect(installed.script.contains("refresh: 9"))
        #expect(!FileManager.default.fileExists(atPath: widgets.appendingPathComponent("old-name").path))
        let kept = try ScriptedWidgetStorage(fileURL: storageURL)
        #expect(kept.get("count") == .number(4))
        let inspection = try ScriptedWidgetInstaller.inspect(second, into: widgets)
        #expect(inspection.replacesExisting)
    }

    @Test func removeDeletesTheFolderAndTheStorageFile() throws {
        let root = try SampleWidget.makeTemporaryDirectory()
        let widgets = root.appendingPathComponent("Widgets", isDirectory: true)
        let source = try SampleWidget.makePackage(manifest: SampleWidget.manifest(), script: script, in: root)
        let installed = try ScriptedWidgetInstaller.install(from: source, into: widgets)
        let storageURL = ScriptedWidgetStorage.fileURL(beside: installed.directory, id: installed.id)
        try Data("{}".utf8).write(to: storageURL)
        try ScriptedWidgetInstaller.remove(installed.directory, id: installed.id, from: widgets)
        #expect(!FileManager.default.fileExists(atPath: installed.directory.path))
        #expect(!FileManager.default.fileExists(atPath: storageURL.path))
    }

    @Test func aSymlinkOutOfThePackageFailsTheLoad() throws {
        let root = try SampleWidget.makeTemporaryDirectory()
        let source = try SampleWidget.makePackage(manifest: SampleWidget.manifest(), script: script, in: root)
        let outside = root.appendingPathComponent("secret.txt")
        try Data("secret".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: source.appendingPathComponent("note"), withDestinationURL: outside)
        #expect(throws: ScriptedWidgetError.self) {
            try ScriptedWidgetPackage.load(from: source)
        }
        let widgets = root.appendingPathComponent("Widgets", isDirectory: true)
        #expect(throws: ScriptedWidgetError.self) {
            try ScriptedWidgetInstaller.install(from: source, into: widgets)
        }
        #expect(!FileManager.default.fileExists(atPath: widgets.appendingPathComponent("com.example.test").path))
    }

    #if os(macOS)
        @Test func installsADeflatedZip() throws {
            let root = try SampleWidget.makeTemporaryDirectory()
            let source = try SampleWidget.makePackage(manifest: SampleWidget.manifest(), script: script, in: root)
            let zip = root.appendingPathComponent("widget.zip")
            let zipTool = Process()
            zipTool.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            zipTool.currentDirectoryURL = root
            zipTool.arguments = ["-r", zip.path, source.lastPathComponent]
            try zipTool.run()
            zipTool.waitUntilExit()
            #expect(zipTool.terminationStatus == 0)
            let installed = try ScriptedWidgetInstaller.install(
                from: zip, into: root.appendingPathComponent("Widgets", isDirectory: true))
            #expect(installed.script == script)
        }
    #endif

    private let script = "function render() { return { elements: [] }; }"
}

@Suite("Scripted diagnostic log")
struct DiagnosticLogTests {
    @Test func dropsTheOldestLinePastTheCap() {
        var log = ScriptedDiagnosticLog()
        for index in 0 ..< (ScriptedDiagnosticLog.capacity + 3) {
            log.record("line \(index)")
        }
        #expect(log.entries.count == ScriptedDiagnosticLog.capacity)
        #expect(log.entries.first?.message == "line 3")
        #expect(log.entries.last?.message == "line \(ScriptedDiagnosticLog.capacity + 2)")
    }
}

/// A stored-method zip, so the installer tests don't need `ditto`.
private enum StoredZip {
    static func archive(_ files: [String: Data]) -> Data {
        var locals = Data()
        var central = Data()
        for name in files.keys.sorted() {
            let bytes = files[name] ?? Data()
            let nameData = Data(name.utf8)
            let local = localHeader(name: nameData, bytes: bytes)
            central.append(centralHeader(name: nameData, bytes: bytes, offset: locals.count))
            locals.append(local)
        }
        var archive = locals
        archive.append(central)
        archive.append(endRecord(count: files.count, centralSize: central.count, centralOffset: locals.count))
        return archive
    }

    private static func localHeader(name: Data, bytes: Data) -> Data {
        var data = Data()
        append(&data, 0x0403_4B50, width: 4)
        append(&data, 20, width: 2)
        append(&data, 0, width: 2)
        append(&data, 0, width: 2)
        append(&data, 0, width: 2)
        append(&data, 0, width: 2)
        append(&data, 0, width: 4)
        append(&data, bytes.count, width: 4)
        append(&data, bytes.count, width: 4)
        append(&data, name.count, width: 2)
        append(&data, 0, width: 2)
        data.append(name)
        data.append(bytes)
        return data
    }

    private static func centralHeader(name: Data, bytes: Data, offset: Int) -> Data {
        var data = Data()
        append(&data, 0x0201_4B50, width: 4)
        append(&data, 20, width: 2)
        append(&data, 20, width: 2)
        append(&data, 0, width: 2)
        append(&data, 0, width: 2)
        append(&data, 0, width: 2)
        append(&data, 0, width: 2)
        append(&data, 0, width: 4)
        append(&data, bytes.count, width: 4)
        append(&data, bytes.count, width: 4)
        append(&data, name.count, width: 2)
        append(&data, 0, width: 2)
        append(&data, 0, width: 2)
        append(&data, 0, width: 2)
        append(&data, 0, width: 2)
        append(&data, 0, width: 4)
        append(&data, offset, width: 4)
        data.append(name)
        return data
    }

    private static func endRecord(count: Int, centralSize: Int, centralOffset: Int) -> Data {
        var data = Data()
        append(&data, 0x0605_4B50, width: 4)
        append(&data, 0, width: 2)
        append(&data, 0, width: 2)
        append(&data, count, width: 2)
        append(&data, count, width: 2)
        append(&data, centralSize, width: 4)
        append(&data, centralOffset, width: 4)
        append(&data, 0, width: 2)
        return data
    }

    private static func append(_ data: inout Data, _ value: Int, width: Int) {
        for shift in 0 ..< width {
            data.append(UInt8((value >> (8 * shift)) & 0xFF))
        }
    }
}
