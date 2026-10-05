import Foundation
import Testing
@testable import DockCore

@Suite("DockStorage migration")
struct MigrationTests {
    /// A v1 `dock.json` as written by builds before the widget ID rename.
    private let legacyJSON = #"""
    {
      "activeProfileID" : "6F0C9E4B-2B57-4C1F-9C55-3C7A8E1D0A01",
      "profiles" : [
        {
          "id" : "6F0C9E4B-2B57-4C1F-9C55-3C7A8E1D0A01",
          "items" : [
            {
              "id" : "0B0B6C2E-8F6E-4B8A-A3B1-7E6F0C1D2A01",
              "kind" : { "spacer" : { "_0" : { "size" : "small" } } }
            },
            {
              "id" : "0B0B6C2E-8F6E-4B8A-A3B1-7E6F0C1D2A02",
              "kind" : { "widget" : { "_0" : { "settings" : { "style" : "analog" }, "typeID" : "org.opendock.widget.clock" } } }
            },
            {
              "id" : "0B0B6C2E-8F6E-4B8A-A3B1-7E6F0C1D2A03",
              "kind" : { "widget" : { "_0" : { "settings" : { }, "typeID" : "org.opendock.widget.calendar" } } }
            }
          ],
          "name" : "Default"
        }
      ],
      "settings" : { },
      "version" : 1
    }
    """#

    private func legacyDocument(_ typeIDs: [String]) -> DockDocument {
        let safari = DockItem.app(at: URL(fileURLWithPath: "/Applications/Safari.app"))
        let work = DockProfile(name: "Work", items: [safari] + typeIDs.map { DockItem.widget($0, settings: ["key": $0]) })
        let home = DockProfile(name: "Home", items: [DockItem.spacer()] + typeIDs.map { DockItem.widget($0) })
        return DockDocument(version: 1, profiles: [work, home], activeProfileID: home.id)
    }

    private func widgetTypeIDs(_ document: DockDocument) -> [[String]] {
        document.profiles.map { $0.items.compactMap(\.widgetInstance?.typeID) }
    }

    @Test func builtInIDsUseCurrentNamespace() {
        for id in [BuiltInWidgetID.clock, BuiltInWidgetID.battery, BuiltInWidgetID.calendar] {
            #expect(id.hasPrefix(DockStorage.widgetIDPrefix))
        }
    }

    @Test func decodesLegacyFileOnDisk() throws {
        let document = try DockStorage.decode(Data(legacyJSON.utf8))

        #expect(document.version == DockDocument.currentVersion)
        let items = document.activeProfile.items
        #expect(items.count == 3)
        #expect(items[0].spacerItem?.size == .small)
        #expect(items[1].widgetInstance == WidgetInstance(typeID: BuiltInWidgetID.clock, settings: ["style": "analog"]))
        #expect(items[2].widgetInstance?.typeID == BuiltInWidgetID.calendar)
        #expect(items[1].id == UUID(uuidString: "0B0B6C2E-8F6E-4B8A-A3B1-7E6F0C1D2A02"))
    }

    @Test func rewritesLegacyIDsInEveryProfile() throws {
        let legacy = legacyDocument([
            "org.opendock.widget.clock",
            "org.opendock.widget.battery",
            "org.opendock.widget.calendar",
        ])

        let migrated = try DockStorage.decode(DockStorage.encode(legacy))

        let expected = [BuiltInWidgetID.clock, BuiltInWidgetID.battery, BuiltInWidgetID.calendar]
        #expect(widgetTypeIDs(migrated) == [expected, expected])
        #expect(migrated.version == DockDocument.currentVersion)
        #expect(migrated.activeProfileID == legacy.activeProfileID)
        #expect(migrated.profiles.map { $0.items.map(\.id) } == legacy.profiles.map { $0.items.map(\.id) })
        #expect(migrated.profiles[0].items[0] == legacy.profiles[0].items[0])
        #expect(migrated.profiles[0].items[1].widgetInstance?.settings == ["key": "org.opendock.widget.clock"])
    }

    @Test func rewritesUnknownLegacyWidgetsByPrefix() throws {
        let legacy = legacyDocument(["org.opendock.widget.weather"])
        let migrated = try DockStorage.decode(DockStorage.encode(legacy))
        #expect(widgetTypeIDs(migrated) == [
            ["com.newyorkcompute.opendock.widget.weather"],
            ["com.newyorkcompute.opendock.widget.weather"],
        ])
    }

    @Test func leavesOtherWidgetIDsAlone() throws {
        let others = ["com.example.widget.weather", "org.opendock.widgets.clock", "org.opendock.widget"]
        let migrated = try DockStorage.decode(DockStorage.encode(legacyDocument(others)))
        #expect(widgetTypeIDs(migrated) == [others, others])
    }

    @Test func migrationIsIdempotent() throws {
        let once = try DockStorage.decode(DockStorage.encode(legacyDocument(["org.opendock.widget.clock"])))
        let twice = try DockStorage.decode(DockStorage.encode(once))
        #expect(twice == once)
    }

    @Test @MainActor func storeLoadsAndResavesLegacyFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("opendock-tests-\(UUID().uuidString)", isDirectory: true)
        let storage = DockStorage(fileURL: dir.appendingPathComponent("dock.json"))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(legacyJSON.utf8).write(to: storage.fileURL)

        let store = DockStore.load(from: storage)
        #expect(store.items.compactMap(\.widgetInstance?.typeID) == [BuiltInWidgetID.clock, BuiltInWidgetID.calendar])

        store.saveNow()
        let written = try String(contentsOf: storage.fileURL, encoding: .utf8)
        #expect(!written.contains("org.opendock"))
        let siblings = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(!siblings.contains { $0.contains("corrupt") })
    }
}
