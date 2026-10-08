import Foundation
import Testing

@testable import DockCore

/// Profiles and their settings add no format version: files written before them must load
/// unchanged, and odd files (hand-edited, or from a newer build) must not lose data or crash.
@Suite("Profile file format")
struct ProfileFileFormatTests {
    /// A v2 `dock.json` as written by builds before profile switching: two profiles (only
    /// reachable by hand-editing back then), and settings without the switching keys.
    private let v2JSON = #"""
        {
          "activeProfileID" : "6F0C9E4B-2B57-4C1F-9C55-3C7A8E1D0A02",
          "profiles" : [
            {
              "id" : "6F0C9E4B-2B57-4C1F-9C55-3C7A8E1D0A01",
              "items" : [
                {
                  "id" : "0B0B6C2E-8F6E-4B8A-A3B1-7E6F0C1D2A01",
                  "kind" : { "app" : { "_0" : { "bundleIdentifier" : "com.apple.Safari", "url" : "file:///Applications/Safari.app/" } } }
                },
                {
                  "id" : "0B0B6C2E-8F6E-4B8A-A3B1-7E6F0C1D2A02",
                  "kind" : { "divider" : { } }
                }
              ],
              "name" : "Work"
            },
            {
              "id" : "6F0C9E4B-2B57-4C1F-9C55-3C7A8E1D0A02",
              "items" : [
                {
                  "id" : "0B0B6C2E-8F6E-4B8A-A3B1-7E6F0C1D2A03",
                  "kind" : { "widget" : { "_0" : { "settings" : { "style" : "analog" }, "typeID" : "com.newyorkcompute.opendock.widget.clock" } } }
                },
                {
                  "id" : "0B0B6C2E-8F6E-4B8A-A3B1-7E6F0C1D2A04",
                  "kind" : { "spacer" : { "_0" : { "size" : "small" } } }
                }
              ],
              "name" : "Home"
            }
          ],
          "settings" : {
            "autoHide" : true,
            "hideAppleDock" : true,
            "iconSize" : 64,
            "magnification" : 1.8
          },
          "version" : 2
        }
        """#

    private func decode(_ json: String) throws -> DockDocument {
        try DockStorage.decode(Data(json.utf8))
    }

    @Test func loadsAVersion2FileUnchanged() throws {
        let doc = try decode(v2JSON)

        #expect(doc.version == 2)
        #expect(doc.profiles.map(\.name) == ["Work", "Home"])
        #expect(doc.activeProfileID == UUID(uuidString: "6F0C9E4B-2B57-4C1F-9C55-3C7A8E1D0A02"))
        #expect(doc.activeProfile.name == "Home")
        #expect(
            doc.profiles.flatMap(\.items).map(\.id.uuidString) == [
                "0B0B6C2E-8F6E-4B8A-A3B1-7E6F0C1D2A01",
                "0B0B6C2E-8F6E-4B8A-A3B1-7E6F0C1D2A02",
                "0B0B6C2E-8F6E-4B8A-A3B1-7E6F0C1D2A03",
                "0B0B6C2E-8F6E-4B8A-A3B1-7E6F0C1D2A04",
            ])
        #expect(doc.profiles[0].items[0].appItem?.bundleIdentifier == "com.apple.Safari")
        #expect(doc.profiles[0].items[1].isDivider)
        #expect(
            doc.profiles[1].items[0].widgetInstance
                == WidgetInstance(typeID: BuiltInWidgetID.clock, settings: ["style": "analog"]))
        #expect(doc.profiles[1].items[1].spacerItem?.size == .small)

        #expect(doc.settings.autoHide)
        #expect(doc.settings.hideAppleDock)
        #expect(doc.settings.iconSize == 64)
        #expect(doc.settings.magnification == 1.8)
        #expect(doc.settings.nextProfileHotKey == nil)
        #expect(doc.settings.previousProfileHotKey == nil)
        #expect(doc.settings.switchProfilesByScrolling)
    }

    @Test func resavingAVersion2FileKeepsEverything() throws {
        let doc = try decode(v2JSON)
        let resaved = try DockStorage.decode(DockStorage.encode(doc))
        #expect(resaved == doc)
    }

    @Test func switchingSettingsRoundTrip() throws {
        var doc = try decode(v2JSON)
        doc.settings.nextProfileHotKey = HotKey(keyCode: 124, modifiers: [.control, .option, .command])
        doc.settings.previousProfileHotKey = HotKey(keyCode: 123, modifiers: [.control, .shift])
        doc.settings.switchProfilesByScrolling = false

        let decoded = try DockStorage.decode(DockStorage.encode(doc))
        #expect(decoded.settings == doc.settings)
    }

    @Test func switchingSettingsDecodeTolerantly() throws {
        let json =
            #"{"nextProfileHotKey": {"keyCode": "right"}, "previousProfileHotKey": 7, "switchProfilesByScrolling": "no"}"#
        let settings = try JSONDecoder().decode(DockSettings.self, from: Data(json.utf8))
        #expect(settings.nextProfileHotKey == nil)
        #expect(settings.previousProfileHotKey == nil)
        #expect(settings.switchProfilesByScrolling == DockSettings.default.switchProfilesByScrolling)
    }

    @Test func unknownOrMissingActiveProfileFallsBackToTheFirst() throws {
        let unknown = v2JSON.replacingOccurrences(
            of: #""activeProfileID" : "6F0C9E4B-2B57-4C1F-9C55-3C7A8E1D0A02","#,
            with: #""activeProfileID" : "00000000-0000-0000-0000-000000000000","#
        )
        #expect(try decode(unknown).activeProfile.name == "Work")

        let missing = v2JSON.replacingOccurrences(
            of: #""activeProfileID" : "6F0C9E4B-2B57-4C1F-9C55-3C7A8E1D0A02","#,
            with: ""
        )
        #expect(try decode(missing).activeProfile.name == "Work")
    }

    @Test func repeatedProfileIDsAreMadeUnique() throws {
        let json = v2JSON.replacingOccurrences(
            of: #""id" : "6F0C9E4B-2B57-4C1F-9C55-3C7A8E1D0A02","#,
            with: #""id" : "6F0C9E4B-2B57-4C1F-9C55-3C7A8E1D0A01","#
        )
        let doc = try decode(json)
        #expect(doc.profiles.map(\.name) == ["Work", "Home"])
        #expect(Set(doc.profiles.map(\.id)).count == 2)
        #expect(doc.profiles[0].id == UUID(uuidString: "6F0C9E4B-2B57-4C1F-9C55-3C7A8E1D0A01"))
        #expect(doc.profiles[1].items.count == 2)
    }

    @Test func aFileWithoutProfilesIsRejected() {
        let json =
            #"{"activeProfileID": "6F0C9E4B-2B57-4C1F-9C55-3C7A8E1D0A01", "profiles": [], "settings": {}, "version": 2}"#
        #expect(throws: DecodingError.self) { try decode(json) }
    }

    @Test @MainActor func storeBacksUpAFileWithoutProfiles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("opendock-tests-\(UUID().uuidString)", isDirectory: true)
        let storage = DockStorage(fileURL: dir.appendingPathComponent("dock.json"))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"activeProfileID": "6F0C9E4B-2B57-4C1F-9C55-3C7A8E1D0A01", "profiles": [], "version": 2}"#.utf8)
            .write(to: storage.fileURL)

        let store = DockStore.load(from: storage)
        #expect(store.profiles.count == 1)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(siblings.contains { $0.contains("corrupt") })
    }
}

@Suite("HotKey")
struct HotKeyTests {
    @Test func globalShortcutsNeedCommandOrControl() {
        #expect(HotKey(keyCode: 0, modifiers: [.command]).isValidGlobalShortcut)
        #expect(HotKey(keyCode: 0, modifiers: [.control, .shift]).isValidGlobalShortcut)
        #expect(!HotKey(keyCode: 0, modifiers: [.option]).isValidGlobalShortcut)
        #expect(!HotKey(keyCode: 0, modifiers: [.option, .shift]).isValidGlobalShortcut)
        #expect(!HotKey(keyCode: 0, modifiers: []).isValidGlobalShortcut)
    }

    @Test func modifierSymbolsUseApplesOrder() {
        #expect(HotKey(keyCode: 0, modifiers: [.command, .shift, .option, .control]).modifierSymbols == "⌃⌥⇧⌘")
        #expect(HotKey(keyCode: 0, modifiers: [.command, .shift]).modifierSymbols == "⇧⌘")
    }
}
