import Foundation
import Testing

@testable import DockCore

@Suite("Divider items")
struct DividerTests {
    /// A v2 `dock.json` as written by builds before dividers existed.
    private let preDividerJSON = #"""
        {
          "activeProfileID" : "7A1D0F5C-3C68-4D2A-8D66-4D8B9F2E1B01",
          "profiles" : [
            {
              "id" : "7A1D0F5C-3C68-4D2A-8D66-4D8B9F2E1B01",
              "items" : [
                {
                  "id" : "1C1C7D3F-9F7F-4C9B-B4C2-8F7A1D2E3B01",
                  "kind" : { "app" : { "_0" : { "bundleIdentifier" : "com.apple.Safari", "url" : "file:///Applications/Safari.app/" } } }
                },
                {
                  "id" : "1C1C7D3F-9F7F-4C9B-B4C2-8F7A1D2E3B02",
                  "kind" : { "spacer" : { "_0" : { "size" : "small" } } }
                },
                {
                  "id" : "1C1C7D3F-9F7F-4C9B-B4C2-8F7A1D2E3B03",
                  "kind" : { "widget" : { "_0" : { "settings" : { }, "typeID" : "com.newyorkcompute.opendock.widget.clock" } } }
                },
                {
                  "id" : "1C1C7D3F-9F7F-4C9B-B4C2-8F7A1D2E3B04",
                  "kind" : { "folder" : { "_0" : { "url" : "file:///Users/me/Downloads/" } } }
                }
              ],
              "name" : "Default"
            }
          ],
          "settings" : { "autoHide" : true },
          "version" : 2
        }
        """#

    private func itemIDs(_ document: DockDocument) -> [String] {
        document.activeProfile.items.map(\.id.uuidString)
    }

    @Test func preDividerFileDecodesUnchanged() throws {
        let document = try DockStorage.decode(Data(preDividerJSON.utf8))

        #expect(document.version == DockDocument.currentVersion)
        #expect(itemIDs(document) == (1 ... 4).map { "1C1C7D3F-9F7F-4C9B-B4C2-8F7A1D2E3B0\($0)" })
        let items = document.activeProfile.items
        #expect(items[0].appItem?.bundleIdentifier == "com.apple.Safari")
        #expect(items[1].spacerItem?.size == .small)
        #expect(items[2].widgetInstance?.typeID == BuiltInWidgetID.clock)
        #expect(items[3].folderItem?.url.normalizedPath == "/Users/me/Downloads")
        #expect(!items.contains(where: { $0.isDivider }))
        #expect(document.settings.autoHide)
    }

    @Test @MainActor func storeDoesNotAddDividersToExistingLayouts() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("opendock-tests-\(UUID().uuidString)", isDirectory: true)
        let storage = DockStorage(fileURL: dir.appendingPathComponent("dock.json"))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(preDividerJSON.utf8).write(to: storage.fileURL)

        let store = DockStore.load(from: storage)
        #expect(store.items.count == 4)
        #expect(!store.items.contains(where: { $0.isDivider }))

        store.saveNow()
        let reloaded = try storage.load()
        #expect(itemIDs(reloaded) == itemIDs(store.document))
        #expect(!reloaded.activeProfile.items.contains(where: { $0.isDivider }))
    }

    @Test func dividerRoundTrips() throws {
        let divider = DockItem.divider()
        let profile = DockProfile(name: "P", items: [.spacer(), divider, .spacer()])
        let document = DockDocument(profiles: [profile], activeProfileID: profile.id)

        let decoded = try DockStorage.decode(DockStorage.encode(document))

        #expect(decoded == document)
        #expect(decoded.activeProfile.items[1].isDivider)
        #expect(decoded.activeProfile.items[1].id == divider.id)
    }

    @Test func decodesDividerJSON() throws {
        let json = #"{ "id" : "1C1C7D3F-9F7F-4C9B-B4C2-8F7A1D2E3B09", "kind" : { "divider" : { } } }"#
        let item = try JSONDecoder().decode(DockItem.self, from: Data(json.utf8))
        #expect(item.kind == .divider)
        #expect(!item.isSpacer && !item.isWidget)
    }

    @Test func dividersReorderLikeOtherItems() {
        let divider = DockItem.divider()
        var profile = DockProfile(name: "P", items: [.spacer(), .spacer(), divider])
        let ids = profile.items.map(\.id)
        profile.move(id: divider.id, before: ids[0])
        #expect(profile.items.map(\.id) == [divider.id, ids[0], ids[1]])
        profile.remove(id: divider.id)
        #expect(profile.items.map(\.id) == [ids[0], ids[1]])
    }

    /// A file from a newer build may contain item kinds this one doesn't know. Those are
    /// skipped; the rest of the dock survives instead of the file being treated as corrupt.
    @Test func skipsUnknownItemKinds() throws {
        let json = preDividerJSON.replacingOccurrences(
            of: #"{ "spacer" : { "_0" : { "size" : "small" } } }"#,
            with: #"{ "stack" : { "_0" : { "url" : "file:///Users/me/Documents/" } } }"#
        )
        #expect(json != preDividerJSON)

        let document = try DockStorage.decode(Data(json.utf8))

        #expect(itemIDs(document) == [1, 3, 4].map { "1C1C7D3F-9F7F-4C9B-B4C2-8F7A1D2E3B0\($0)" })
    }

    @Test func profileWithoutItemsKeyDecodesEmpty() throws {
        let json = #"{ "id" : "7A1D0F5C-3C68-4D2A-8D66-4D8B9F2E1B01", "name" : "Empty" }"#
        let profile = try JSONDecoder().decode(DockProfile.self, from: Data(json.utf8))
        #expect(profile.items.isEmpty)
        #expect(profile.name == "Empty")
    }
}
