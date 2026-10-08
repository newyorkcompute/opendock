import Foundation
import Observation
import Testing

@testable import DockCore

/// Set from an observation's `onChange`, which runs synchronously during the mutation.
private final class ChangeFlag: @unchecked Sendable {
    var isSet = false
}

@Suite("Welcome window")
@MainActor
struct WelcomeTests {
    private func temporaryStorage() -> DockStorage {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("opendock-tests-\(UUID().uuidString)", isDirectory: true)
        return DockStorage(fileURL: dir.appendingPathComponent("dock.json"))
    }

    private func write(_ data: Data, to storage: DockStorage) throws {
        try FileManager.default.createDirectory(
            at: storage.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: storage.fileURL)
    }

    @Test func freshInstallNeedsWelcome() throws {
        let storage = temporaryStorage()
        let store = DockStore.load(from: storage)
        #expect(store.needsWelcome)
        #expect(try !storage.load().hasSeenWelcome)
    }

    @Test func freshInstallStillNeedsWelcomeUntilItIsSeen() {
        let storage = temporaryStorage()
        _ = DockStore.load(from: storage)
        #expect(DockStore.load(from: storage).needsWelcome)
    }

    @Test func seenWelcomeIsPersisted() {
        let storage = temporaryStorage()
        let store = DockStore.load(from: storage)
        store.markWelcomeSeen()
        #expect(!store.needsWelcome)
        store.saveNow()
        #expect(!DockStore.load(from: storage).needsWelcome)
    }

    /// The dock holds widgets' permission prompts while `needsWelcome` is true, and lets them
    /// ask once it observes the change.
    @Test func seeingTheWelcomeNotifiesObservers() {
        let store = DockStore.load(from: temporaryStorage())
        let changed = ChangeFlag()
        let needsWelcome = withObservationTracking {
            store.needsWelcome
        } onChange: {
            changed.isSet = true
        }
        #expect(needsWelcome)

        store.markWelcomeSeen()
        #expect(changed.isSet)
        #expect(!store.needsWelcome)
    }

    @Test func existingFileFromBeforeTheWelcomeWindowDoesNotNeedIt() throws {
        let storage = temporaryStorage()
        var json = try #require(
            JSONSerialization.jsonObject(with: DockStorage.encode(.firstRun())) as? [String: Any])
        json["hasSeenWelcome"] = nil
        try write(JSONSerialization.data(withJSONObject: json), to: storage)

        #expect(!DockStore.load(from: storage).needsWelcome)
    }

    @Test func existingFileThatSawTheWelcomeDoesNotNeedIt() throws {
        let storage = temporaryStorage()
        try write(DockStorage.encode(.firstRun()), to: storage)
        #expect(!DockStore.load(from: storage).needsWelcome)
    }

    @Test func unreadableFileDoesNotNeedWelcome() throws {
        let storage = temporaryStorage()
        try write(Data("not json".utf8), to: storage)
        #expect(!DockStore.load(from: storage).needsWelcome)
    }

    @Test func flagDecodesTolerantly() throws {
        var json = try #require(
            JSONSerialization.jsonObject(with: DockStorage.encode(.firstRun())) as? [String: Any])
        json["hasSeenWelcome"] = "no"
        #expect(try DockStorage.decode(JSONSerialization.data(withJSONObject: json)).hasSeenWelcome)

        var unseen = DockDocument.firstRun()
        unseen.hasSeenWelcome = false
        #expect(try !DockStorage.decode(DockStorage.encode(unseen)).hasSeenWelcome)
    }

    @Test func resetKeepsTheFlag() {
        let store = DockStore.load(from: temporaryStorage())
        store.resetToFirstRun()
        #expect(store.needsWelcome)

        store.markWelcomeSeen()
        store.resetToFirstRun()
        #expect(!store.needsWelcome)
    }

    @Test func importKeepsTheFlag() throws {
        var unseen = DockDocument.firstRun()
        unseen.hasSeenWelcome = false

        let seenStore = DockStore(storage: temporaryStorage(), document: .firstRun(), saveDelay: .zero)
        try seenStore.importData(DockStorage.encode(unseen))
        #expect(!seenStore.needsWelcome)

        let freshStore = DockStore.load(from: temporaryStorage())
        try freshStore.importData(DockStorage.encode(.firstRun()))
        #expect(freshStore.needsWelcome)
    }
}

@Suite("Replacing apps")
struct ReplaceAppsTests {
    private let safari = URL(fileURLWithPath: "/Applications/Safari.app")
    private let mail = URL(fileURLWithPath: "/System/Applications/Mail.app")
    private let notes = URL(fileURLWithPath: "/System/Applications/Notes.app")

    @Test func replacesAppsInPlaceAndKeepsOtherItems() {
        let divider = DockItem.divider()
        let clock = DockItem.widget(BuiltInWidgetID.clock)
        let downloads = DockItem.folder(at: URL(fileURLWithPath: "/Users/me/Downloads"))
        var profile = DockProfile(
            name: "Default", items: [clock, .app(at: safari), .app(at: mail), divider, downloads])

        profile.replaceApps(with: [notes, safari])

        #expect(
            profile.items.compactMap(\.appItem?.url.normalizedPath) == [notes.normalizedPath, safari.normalizedPath])
        #expect(profile.items.first?.id == clock.id)
        #expect(profile.items.suffix(2).map(\.id) == [divider.id, downloads.id])
    }

    @Test func skipsDuplicates() {
        var profile = DockProfile(name: "Default")
        profile.replaceApps(with: [safari, URL(fileURLWithPath: "/Applications/Safari.app/"), mail])
        #expect(
            profile.items.compactMap(\.appItem?.url.normalizedPath) == [safari.normalizedPath, mail.normalizedPath])
    }

    @Test func putsAppsFirstWhenThereWereNone() {
        let clock = DockItem.widget(BuiltInWidgetID.clock)
        var profile = DockProfile(name: "Default", items: [clock])
        profile.replaceApps(with: [mail])
        #expect(profile.items.first?.appItem?.url.normalizedPath == mail.normalizedPath)
        #expect(profile.items.last?.id == clock.id)
    }
}
