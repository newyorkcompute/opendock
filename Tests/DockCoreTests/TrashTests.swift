import Foundation
import Testing

@testable import DockCore

@Suite("Trash item")
struct TrashItemTests {
    @Test func roundTripsThroughJSON() throws {
        let item = DockItem.trash()
        let data = try JSONEncoder().encode(item)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let kind = try #require(json["kind"] as? [String: Any])
        #expect(kind.keys.sorted() == ["trash"])

        let decoded = try JSONDecoder().decode(DockItem.self, from: data)
        #expect(decoded == item)
        #expect(decoded.isTrash)
    }

    @Test func decodesTheStoredForm() throws {
        let json = #"{ "id" : "0B0B6C2E-8F6E-4B8A-A3B1-7E6F0C1D2A09", "kind" : { "trash" : { } } }"#
        let item = try JSONDecoder().decode(DockItem.self, from: Data(json.utf8))
        #expect(item.isTrash)
        #expect(item.kind == .trash)
    }

    @Test func doesNotMagnifyLikeAWidget() {
        #expect(DockMagnification.growth(for: .trash()) == 1)
        #expect(DockMagnification.growth(for: .trash()) == DockMagnification.growth(for: .divider()) + 1)
    }
}

@Suite("Trash in a profile")
struct TrashProfileTests {
    private let safari = DockItem.app(at: URL(fileURLWithPath: "/Applications/Safari.app"))
    private let mail = DockItem.app(at: URL(fileURLWithPath: "/System/Applications/Mail.app"))

    @Test func staysLastWhenCreatedOutOfOrder() {
        let trash = DockItem.trash()
        let profile = DockProfile(name: "Default", items: [trash, safari, mail])
        #expect(profile.items.map(\.id) == [safari.id, mail.id, trash.id])
        #expect(profile.pinnedItems.map(\.id) == [safari.id, mail.id])
        #expect(profile.trashItem?.id == trash.id)
        #expect(profile.showsTrash)
    }

    @Test func keepsOnlyTheFirstOfSeveral() {
        let first = DockItem.trash()
        let second = DockItem.trash()
        let profile = DockProfile(name: "Default", items: [first, safari, second])
        #expect(profile.items.map(\.id) == [safari.id, first.id])
    }

    @Test func appendAndInsertGoBeforeTheTrash() {
        var profile = DockProfile(name: "Default", items: [safari, .trash()])
        profile.append(mail)
        #expect(profile.items.map(\.kind).last == .trash)
        #expect(profile.pinnedItems.map(\.id) == [safari.id, mail.id])

        let divider = DockItem.divider()
        profile.insert(divider, at: profile.items.count)
        #expect(profile.items.map(\.kind).last == .trash)
        #expect(profile.pinnedItems.map(\.id) == [safari.id, mail.id, divider.id])
        #expect(profile.index(after: nil) == 3)
    }

    @Test func movesDoNotDisplaceTheTrash() {
        let trash = DockItem.trash()
        var profile = DockProfile(name: "Default", items: [safari, mail, trash])

        profile.move(id: safari.id, to: 2)
        #expect(profile.items.map(\.id) == [mail.id, safari.id, trash.id])

        profile.move(id: trash.id, to: 0)
        #expect(profile.items.map(\.id) == [mail.id, safari.id, trash.id])

        profile.move(id: mail.id, before: trash.id)
        #expect(profile.items.last?.id == trash.id)
    }

    @Test func replacingAppsKeepsTheTrashLast() {
        let trash = DockItem.trash()
        var profile = DockProfile(name: "Default", items: [safari, trash])
        profile.replaceApps(with: [mail.appItem!.url, safari.appItem!.url])
        #expect(profile.items.last?.id == trash.id)
        #expect(profile.pinnedItems.count == 2)
    }

    @Test func showsTrashTogglesWithoutChangingAnExistingID() {
        var profile = DockProfile(name: "Default", items: [safari])
        #expect(!profile.showsTrash)
        #expect(profile.trashItem == nil)

        profile.showsTrash = true
        let id = profile.trashItem?.id
        #expect(id != nil)
        #expect(profile.items.last?.isTrash == true)

        profile.showsTrash = true
        #expect(profile.trashItem?.id == id)
        #expect(profile.items.count == 2)

        profile.showsTrash = false
        #expect(!profile.showsTrash)
        #expect(profile.items.map(\.id) == [safari.id])
    }

    @Test func aFileWithTheTrashInTheMiddleLoadsWithItLast() throws {
        let json = #"""
            {
              "id" : "6F0C9E4B-2B57-4C1F-9C55-3C7A8E1D0A01",
              "name" : "Work",
              "items" : [
                { "id" : "0B0B6C2E-8F6E-4B8A-A3B1-7E6F0C1D2A01", "kind" : { "trash" : { } } },
                { "id" : "0B0B6C2E-8F6E-4B8A-A3B1-7E6F0C1D2A02", "kind" : { "divider" : { } } }
              ]
            }
            """#
        let profile = try JSONDecoder().decode(DockProfile.self, from: Data(json.utf8))
        #expect(
            profile.items.map(\.id.uuidString) == [
                "0B0B6C2E-8F6E-4B8A-A3B1-7E6F0C1D2A02", "0B0B6C2E-8F6E-4B8A-A3B1-7E6F0C1D2A01",
            ])
        #expect(profile.showsTrash)
    }
}

@Suite("Trash in the document and store")
@MainActor
struct TrashStoreTests {
    private func temporaryStorage() -> DockStorage {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("opendock-tests-\(UUID().uuidString)", isDirectory: true)
        return DockStorage(fileURL: dir.appendingPathComponent("dock.json"))
    }

    @Test func freshInstallEndsWithTheTrash() {
        let items = DockDocument.firstRun().activeProfile.items
        #expect(items.last?.isTrash == true)
        #expect(items.count { $0.isTrash } == 1)
    }

    @Test func existingFilesDoNotGainATrash() throws {
        let profile = DockProfile(name: "Mine", items: [.divider(), .spacer()])
        let document = DockDocument(profiles: [profile], activeProfileID: profile.id)
        let reloaded = try DockStorage.decode(DockStorage.encode(document))
        #expect(!reloaded.activeProfile.showsTrash)
        #expect(reloaded.activeProfile.items.count == 2)
    }

    @Test func storeHidesTheTrashFromItsItems() {
        let store = DockStore(storage: temporaryStorage(), document: .firstRun(), saveDelay: .zero)
        #expect(store.showsTrash)
        #expect(!store.items.contains { $0.isTrash })
        #expect(store.profile.items.last?.isTrash == true)
    }

    @Test func storeTogglesAndPersistsTheTrash() throws {
        let storage = temporaryStorage()
        let store = DockStore(storage: storage, document: .firstRun(), saveDelay: .zero)
        let pinned = store.items

        store.setShowsTrash(false)
        store.saveNow()
        #expect(!store.showsTrash)
        #expect(store.items == pinned)
        #expect(try !storage.load().activeProfile.showsTrash)

        store.setShowsTrash(true)
        store.saveNow()
        #expect(store.showsTrash)
        #expect(store.items == pinned)
        #expect(try storage.load().activeProfile.items.last?.isTrash == true)
    }

    @Test func appendingToTheStoreKeepsTheTrashLast() {
        let store = DockStore(storage: temporaryStorage(), document: .firstRun(), saveDelay: .zero)
        let spacer = DockItem.spacer()
        store.append(spacer)
        #expect(store.items.last?.id == spacer.id)
        #expect(store.profile.items.last?.isTrash == true)

        store.remove(id: store.profile.trashItem!.id)
        #expect(!store.showsTrash)
    }
}

@Suite("Trash contents")
struct TrashContentsTests {
    @Test func finderHousekeepingFilesDoNotCount() {
        #expect(TrashContents.isEmpty(itemNames: []))
        #expect(TrashContents.isEmpty(itemNames: [".DS_Store", ".localized"]))
        #expect(!TrashContents.isEmpty(itemNames: [".DS_Store", "Old Report.pdf"]))
        #expect(!TrashContents.isEmpty(itemNames: [".hidden"]))
    }

    @Test func readsFindersCount() {
        #expect(TrashContents.itemCount(inFinderReply: "3\n") == 3)
        #expect(TrashContents.itemCount(inFinderReply: " 0 ") == 0)
        #expect(TrashContents.itemCount(inFinderReply: nil) == nil)
        #expect(TrashContents.itemCount(inFinderReply: "") == nil)
        #expect(TrashContents.itemCount(inFinderReply: "execution error: Not authorized") == nil)
    }

    @Test func emptyingDoesNotWaitForFindersConfirmation() {
        #expect(TrashContents.emptyScript.contains("ignoring application responses"))
        #expect(TrashContents.emptyScript.contains("empty trash"))
        #expect(TrashContents.countScript.contains("count items of trash"))
    }
}
