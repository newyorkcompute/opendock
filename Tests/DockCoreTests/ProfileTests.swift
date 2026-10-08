import Foundation
import Testing

@testable import DockCore

@Suite("Profiles")
struct ProfileTests {
    private func document(_ names: [String], active: Int = 0) -> DockDocument {
        let profiles = names.map {
            DockProfile(name: $0, items: [.spacer(), .widget(BuiltInWidgetID.clock, settings: ["style": "analog"])])
        }
        return DockDocument(profiles: profiles, activeProfileID: profiles[active].id)
    }

    private func names(_ document: DockDocument) -> [String] {
        document.profiles.map(\.name)
    }

    @Test func offsetFromActiveWrapsAround() {
        let doc = document(["A", "B", "C"], active: 2)
        let ids = doc.profiles.map(\.id)
        #expect(doc.profileID(offsetFromActive: 1) == ids[0])
        #expect(doc.profileID(offsetFromActive: -1) == ids[1])
        #expect(doc.profileID(offsetFromActive: -5) == ids[0])
        #expect(doc.profileID(offsetFromActive: 0) == ids[2])
    }

    @Test func activateIgnoresUnknownIDs() {
        var doc = document(["A", "B"])
        let before = doc.activeProfileID
        doc.activateProfile(UUID())
        #expect(doc.activeProfileID == before)
        doc.activateProfile(doc.profiles[1].id)
        #expect(doc.activeProfileID == doc.profiles[1].id)
    }

    @Test func newProfilesAreEmptyNumberedAndInactive() {
        var doc = document(["Default"])
        let active = doc.activeProfileID
        let id = doc.addProfile()
        #expect(doc.activeProfileID == active)
        #expect(doc.profiles.last?.id == id)
        #expect(doc.profiles.last?.items.isEmpty == true)
        doc.addProfile()
        #expect(names(doc) == ["Default", "Profile 2", "Profile 3"])

        doc.renameProfile(doc.profiles[1].id, to: "Profile 4")
        doc.addProfile()
        #expect(names(doc).last == "Profile 5")
    }

    @Test func namedProfilesAvoidTakenNames() {
        var doc = document(["Work"])
        doc.addProfile(named: "  Work ")
        doc.addProfile(named: "Home")
        doc.addProfile(named: "   ")
        #expect(names(doc) == ["Work", "Work 2", "Home", "Profile 4"])
    }

    @Test func duplicateCopiesItemsWithNewIDsAfterTheOriginal() throws {
        var doc = document(["Work", "Home"])
        let source = doc.profiles[0]
        let duplicated = doc.duplicateProfile(source.id)
        let id = try #require(duplicated)
        #expect(names(doc) == ["Work", "Work Copy", "Home"])
        let copy = doc.profiles[1]
        #expect(copy.id == id)
        #expect(copy.items.map(\.kind) == source.items.map(\.kind))
        #expect(Set(copy.items.map(\.id)).isDisjoint(with: source.items.map(\.id)))
        #expect(doc.activeProfileID == source.id)

        doc.duplicateProfile(source.id)
        #expect(names(doc) == ["Work", "Work Copy 2", "Work Copy", "Home"])
        let missing = doc.duplicateProfile(UUID())
        #expect(missing == nil)
    }

    @Test func renameTrimsAndIgnoresBlankNames() {
        var doc = document(["A", "B"])
        let id = doc.profiles[0].id
        doc.renameProfile(id, to: "  Focus  ")
        #expect(doc.profiles[0].name == "Focus")
        doc.renameProfile(id, to: " \n ")
        #expect(doc.profiles[0].name == "Focus")
        doc.renameProfile(id, to: "B")
        #expect(names(doc) == ["B", "B"])
    }

    @Test func deleteKeepsTheLastProfile() {
        var doc = document(["Only"])
        let deletedOnly = doc.deleteProfile(doc.profiles[0].id)
        #expect(!deletedOnly)
        #expect(doc.profiles.count == 1)
        let deletedUnknown = doc.deleteProfile(UUID())
        #expect(!deletedUnknown)
    }

    @Test func deletingTheActiveProfileActivatesItsNeighbor() {
        var doc = document(["A", "B", "C"], active: 1)
        let ids = doc.profiles.map(\.id)
        let deletedB = doc.deleteProfile(ids[1])
        #expect(deletedB)
        #expect(doc.activeProfileID == ids[2])

        let deletedC = doc.deleteProfile(ids[2])
        #expect(deletedC)
        #expect(doc.activeProfileID == ids[0])
        #expect(names(doc) == ["A"])
    }

    @Test func deletingAnInactiveProfileKeepsTheActiveOne() {
        var doc = document(["A", "B", "C"], active: 2)
        let active = doc.activeProfileID
        doc.deleteProfile(doc.profiles[0].id)
        #expect(doc.activeProfileID == active)
        #expect(names(doc) == ["B", "C"])
    }

    @Test func moveStopsAtTheEnds() {
        var doc = document(["A", "B", "C"])
        let a = doc.profiles[0].id
        doc.moveProfile(a, by: 1)
        #expect(names(doc) == ["B", "A", "C"])
        doc.moveProfile(a, by: 5)
        #expect(names(doc) == ["B", "C", "A"])
        doc.moveProfile(a, by: -9)
        #expect(names(doc) == ["A", "B", "C"])
        #expect(doc.activeProfileID == a)
    }
}

@Suite("Profiles in DockStore")
@MainActor
struct ProfileStoreTests {
    private func store(_ storage: DockStorage = Self.temporaryStorage()) -> DockStore {
        DockStore(storage: storage, document: .firstRun(), saveDelay: .zero)
    }

    private static func temporaryStorage() -> DockStorage {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("opendock-tests-\(UUID().uuidString)", isDirectory: true)
        return DockStorage(fileURL: dir.appendingPathComponent("dock.json"))
    }

    @Test func itemEditsGoToTheSelectedProfile() throws {
        let store = store()
        let first = store.activeProfileID
        let firstItems = store.items
        let second = store.addProfile(named: "Empty")
        store.selectProfile(second)
        #expect(store.items.isEmpty)

        store.append(.divider())
        #expect(store.items.count == 1)
        #expect(store.document.profile(id: first)?.items == firstItems)

        store.selectProfile(first)
        #expect(store.items == firstItems)
    }

    @Test func profileChangesPersist() throws {
        let storage = Self.temporaryStorage()
        let store = store(storage)
        let copy = try #require(store.duplicateProfile(store.activeProfileID))
        store.renameProfile(copy, to: "Travel")
        store.selectProfile(copy)
        store.saveNow()

        let reloaded = try storage.load()
        #expect(reloaded.profiles.map(\.name) == ["Default", "Travel"])
        #expect(reloaded.activeProfileID == copy)
    }

    @Test func deletingTheActiveProfileFromTheStore() {
        let store = store()
        let first = store.activeProfileID
        let second = store.addProfile()
        store.selectProfile(second)
        #expect(store.deleteProfile(second))
        #expect(store.activeProfileID == first)
        #expect(!store.deleteProfile(first))
    }

    @Test func selectingTheActiveOrAnUnknownProfileChangesNothing() {
        let store = store()
        let before = store.document
        store.selectProfile(store.activeProfileID)
        store.selectProfile(UUID())
        store.renameProfile(store.activeProfileID, to: " Default ")
        #expect(store.document == before)
    }
}
