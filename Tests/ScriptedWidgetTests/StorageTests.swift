import Foundation
import ScriptedWidgetRuntime
import Testing

@Suite("Scripted widget storage")
struct StorageTests {
    private func storage(limit: Int = 256) throws -> ScriptedWidgetStorage {
        var limits = ScriptedWidgetLimits()
        limits.maxStorageBytes = limit
        let directory = try SampleWidget.makeTemporaryDirectory()
        let file = directory.appendingPathComponent("com.example.test.storage.json")
        return try ScriptedWidgetStorage(fileURL: file, limits: limits)
    }

    @Test func roundTripsJSONValues() throws {
        let store = try storage()
        #expect(store.get("missing") == nil)
        try store.set("count", value: .number(3))
        try store.set("name", value: .string("ticks"))
        try store.set("on", value: .bool(true))
        try store.set("extra", value: .object(["n": .null]))
        #expect(store.get("count") == .number(3))
        #expect(store.get("name") == .string("ticks"))
        #expect(store.get("on") == .bool(true))
        #expect(store.jsonString(for: "name") == "\"ticks\"")

        let again = try ScriptedWidgetStorage(fileURL: store.fileURL, limits: store.limits)
        #expect(again.get("count") == .number(3))
        #expect(again.get("extra") == .object(["n": .null]))
    }

    @Test func removingAKeyDeletesIt() throws {
        let store = try storage()
        try store.set("count", value: .number(1))
        try store.set("count", value: nil)
        #expect(store.get("count") == nil)
        let again = try ScriptedWidgetStorage(fileURL: store.fileURL, limits: store.limits)
        #expect(again.get("count") == nil)
    }

    @Test func refusesAValueThatWouldPassTheCapAndKeepsTheFile() throws {
        let store = try storage(limit: 40)
        try store.set("ok", value: .string("hi"))
        let before = try Data(contentsOf: store.fileURL)
        do {
            try store.set("blob", value: .string(String(repeating: "x", count: 80)))
            Issue.record("a value over the cap was stored")
        } catch {
            guard case .storageTooLarge = error else {
                Issue.record("expected storageTooLarge, got \(error)")
                return
            }
        }
        #expect(store.get("blob") == nil)
        #expect(store.get("ok") == .string("hi"))
        #expect(try Data(contentsOf: store.fileURL) == before)
    }

    @Test func acceptsADocumentExactlyAtTheCap() throws {
        var limits = ScriptedWidgetLimits()
        let directory = try SampleWidget.makeTemporaryDirectory()
        let file = directory.appendingPathComponent("com.example.test.storage.json")
        let value = String(repeating: "a", count: 8)
        let document = try ScriptedWidgetStorage.encode(["k": .string(value)])
        limits.maxStorageBytes = document.count
        let store = try ScriptedWidgetStorage(fileURL: file, limits: limits)
        try store.set("k", value: .string(value))
        #expect(try Data(contentsOf: file).count == document.count)
    }

    @Test func refusesAnUnreadableFile() throws {
        var limits = ScriptedWidgetLimits()
        limits.maxStorageBytes = 100
        let directory = try SampleWidget.makeTemporaryDirectory()
        let file = directory.appendingPathComponent("com.example.test.storage.json")
        try Data("[]".utf8).write(to: file)
        #expect(throws: ScriptedWidgetError.storageUnreadable) {
            _ = try ScriptedWidgetStorage(fileURL: file, limits: limits)
        }
    }

    @Test func fileSitsBesideThePackage() {
        let package = URL(fileURLWithPath: "/tmp/OpenDock/Widgets/hello", isDirectory: true)
        let file = ScriptedWidgetStorage.fileURL(beside: package, id: "com.example.hello")
        #expect(file.lastPathComponent == "com.example.hello.storage.json")
        #expect(file.deletingLastPathComponent().lastPathComponent == "Widgets")
    }
}
