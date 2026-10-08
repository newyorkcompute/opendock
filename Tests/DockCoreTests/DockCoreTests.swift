import Foundation
import Testing

@testable import DockCore

@Suite("DockProfile mutations")
struct DockProfileTests {
    private func profile(_ count: Int) -> DockProfile {
        DockProfile(name: "Test", items: (0 ..< count).map { _ in .spacer() })
    }

    @Test func moveForward() {
        var p = profile(4)
        let ids = p.items.map(\.id)
        p.move(id: ids[0], to: 2)
        #expect(p.items.map(\.id) == [ids[1], ids[2], ids[0], ids[3]])
    }

    @Test func moveBackward() {
        var p = profile(4)
        let ids = p.items.map(\.id)
        p.move(id: ids[3], to: 0)
        #expect(p.items.map(\.id) == [ids[3], ids[0], ids[1], ids[2]])
    }

    @Test func moveBeforeTarget() {
        var p = profile(4)
        let ids = p.items.map(\.id)
        p.move(id: ids[0], before: ids[3])
        #expect(p.items.map(\.id) == [ids[1], ids[2], ids[0], ids[3]])
        p.move(id: ids[3], before: ids[1])
        #expect(p.items.map(\.id) == [ids[3], ids[1], ids[2], ids[0]])
    }

    @Test func moveClampsOutOfRange() {
        var p = profile(3)
        let ids = p.items.map(\.id)
        p.move(id: ids[0], to: 99)
        #expect(p.items.last?.id == ids[0])
        p.move(id: ids[0], to: -5)
        #expect(p.items.first?.id == ids[0])
    }

    @Test func removeAndInsert() {
        var p = profile(2)
        let spacer = DockItem.spacer(.small)
        p.insert(spacer, at: 1)
        #expect(p.items.count == 3)
        #expect(p.items[1].id == spacer.id)
        p.remove(id: spacer.id)
        #expect(p.items.count == 2)
    }

    @Test func containsAppIsPathNormalized() {
        var p = profile(0)
        p.append(.app(at: URL(fileURLWithPath: "/Applications/Safari.app/")))
        #expect(p.containsApp(at: URL(fileURLWithPath: "/Applications/Safari.app")))
        #expect(!p.containsApp(at: URL(fileURLWithPath: "/Applications/Mail.app")))
    }
}

@Suite("DockDocument codec")
struct DockDocumentCodecTests {
    @Test func roundTripsEveryItemKind() throws {
        let profile = DockProfile(
            name: "Work",
            items: [
                .app(at: URL(fileURLWithPath: "/Applications/Safari.app")),
                .folder(at: URL(fileURLWithPath: "/Users/me/Downloads")),
                .spacer(.small),
                .widget(BuiltInWidgetID.clock, settings: ["style": "analog"]),
                .divider(),
            ])
        var settings = DockSettings.default
        settings.iconSize = 64
        settings.autoHide = true
        let original = DockDocument(profiles: [profile], activeProfileID: profile.id, settings: settings)

        let data = try DockStorage.encode(original)
        let decoded = try DockStorage.decode(data)

        #expect(decoded == original)
    }

    @Test func settingsDecodeWithMissingKeys() throws {
        let json = #"{"iconSize": 40}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(DockSettings.self, from: json)
        #expect(settings.iconSize == 40)
        #expect(settings.autoHide == DockSettings.default.autoHide)
        #expect(settings.material == DockSettings.default.material)
    }

    @Test func hideAppleDockDecodesTolerantly() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode(DockSettings.self, from: Data("{}".utf8)).hideAppleDock == false)
        #expect(
            try decoder.decode(DockSettings.self, from: Data(#"{"hideAppleDock": "yes"}"#.utf8)).hideAppleDock == false)

        var settings = DockSettings.default
        settings.hideAppleDock = true
        let decoded = try decoder.decode(DockSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.hideAppleDock)
    }

    @Test func animateOpeningAppsDecodesTolerantly() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode(DockSettings.self, from: Data("{}".utf8)).animateOpeningApps)
        #expect(
            try decoder.decode(DockSettings.self, from: Data(#"{"animateOpeningApps": "no"}"#.utf8)).animateOpeningApps)

        var settings = DockSettings.default
        settings.animateOpeningApps = false
        let decoded = try decoder.decode(DockSettings.self, from: JSONEncoder().encode(settings))
        #expect(!decoded.animateOpeningApps)
    }

    @Test func clickToMinimizeIsOffUnlessTurnedOn() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode(DockSettings.self, from: Data("{}".utf8)).clickToMinimize == false)
        #expect(
            try decoder.decode(DockSettings.self, from: Data(#"{"clickToMinimize": "yes"}"#.utf8)).clickToMinimize
                == false)

        var settings = DockSettings.default
        settings.clickToMinimize = true
        let decoded = try decoder.decode(DockSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.clickToMinimize)
    }

    @Test func showBadgesDecodesTolerantly() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode(DockSettings.self, from: Data("{}".utf8)).showBadges)
        #expect(try decoder.decode(DockSettings.self, from: Data(#"{"showBadges": "no"}"#.utf8)).showBadges)

        var settings = DockSettings.default
        settings.showBadges = false
        let decoded = try decoder.decode(DockSettings.self, from: JSONEncoder().encode(settings))
        #expect(!decoded.showBadges)
    }

    @Test func rejectsNewerVersions() throws {
        let profile = DockProfile(name: "X")
        let doc = DockDocument(
            version: DockDocument.currentVersion + 1, profiles: [profile], activeProfileID: profile.id)
        let data = try JSONEncoder().encode(doc)
        #expect(throws: DockStorage.StorageError.self) {
            try DockStorage.decode(data)
        }
    }

    @Test func activeProfileFallsBackWhenIDUnknown() {
        let a = DockProfile(name: "A")
        let doc = DockDocument(profiles: [a], activeProfileID: UUID())
        #expect(doc.activeProfileID == a.id)
    }

    @Test func firstRunHasWidgetsAndAtLeastOneApp() {
        let doc = DockDocument.firstRun()
        let items = doc.activeProfile.items
        #expect(items.contains { $0.widgetInstance?.typeID == BuiltInWidgetID.clock })
        #expect(items.contains { $0.appItem != nil })
    }

    @Test func firstRunSeparatesGroupsWithDividers() throws {
        let items = DockDocument.firstRun().activeProfile.items
        let firstWidget = try #require(items.firstIndex(where: { $0.isWidget }))
        #expect(items[firstWidget - 1].isDivider)
        if let folder = items.firstIndex(where: { $0.folderItem != nil }) {
            #expect(items[folder - 1].isDivider)
        }
        #expect(!items.contains(where: { $0.isSpacer }))
    }
}

@Suite("DockStore persistence")
@MainActor
struct DockStoreTests {
    private func temporaryStorage() -> DockStorage {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("opendock-tests-\(UUID().uuidString)", isDirectory: true)
        return DockStorage(fileURL: dir.appendingPathComponent("dock.json"))
    }

    @Test func seedsFirstRunWhenMissing() {
        let storage = temporaryStorage()
        let store = DockStore.load(from: storage)
        #expect(storage.exists)
        #expect(!store.items.isEmpty)
    }

    @Test func persistsMutations() throws {
        let storage = temporaryStorage()
        let store = DockStore(storage: storage, document: .firstRun(), saveDelay: .zero)
        let before = store.items.count
        store.append(.spacer())
        store.saveNow()

        let reloaded = try storage.load()
        #expect(reloaded.activeProfile.items.count == before + 1)
    }

    @Test func importReplacesDocument() throws {
        let storage = temporaryStorage()
        let store = DockStore(storage: storage, document: .firstRun(), saveDelay: .zero)

        let profile = DockProfile(name: "Imported", items: [.spacer()])
        let incoming = DockDocument(profiles: [profile], activeProfileID: profile.id)
        try store.importData(DockStorage.encode(incoming))

        #expect(store.profile.name == "Imported")
        #expect(store.items.count == 1)
    }

    @Test func backsUpCorruptFile() throws {
        let storage = temporaryStorage()
        try FileManager.default.createDirectory(
            at: storage.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: storage.fileURL)

        let store = DockStore.load(from: storage)
        #expect(!store.items.isEmpty)

        let siblings = try FileManager.default.contentsOfDirectory(
            atPath: storage.fileURL.deletingLastPathComponent().path)
        #expect(siblings.contains { $0.contains("corrupt") })
    }
}
