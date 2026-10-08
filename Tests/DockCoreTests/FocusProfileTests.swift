import Foundation
import Testing

@testable import DockCore

@Suite("Focus modes and profiles")
struct FocusProfileTests {
    private let work = "com.apple.focus.work"
    private let sleep = "com.apple.sleep.sleep-mode"
    private let doNotDisturb = "com.apple.donotdisturb.mode.default"

    /// Home, Work, and Play profiles, with Home showing. Work Focus shows Work, Sleep shows Play.
    private func document(whenFocusEnds: FocusProfileRules.FocusEnd = .returnToPrevious) -> DockDocument {
        let profiles = ["Home", "Work", "Play"].map { DockProfile(name: $0) }
        var doc = DockDocument(profiles: profiles, activeProfileID: profiles[0].id)
        doc.settings.focusRules = FocusProfileRules(
            profileByMode: [work: profiles[1].id, sleep: profiles[2].id],
            whenFocusEnds: whenFocusEnds)
        return doc
    }

    private func id(_ name: String, in doc: DockDocument) -> DockProfile.ID {
        doc.profiles.first(where: { $0.name == name })!.id
    }

    @Test func aFocusWithAProfileSwitchesToIt() {
        var doc = document()
        #expect(doc.profileForFocusChange(to: work) == id("Work", in: doc))
        #expect(
            doc.focusSwitch
                == FocusProfileSwitch(previousProfileID: id("Home", in: doc), focusProfileID: id("Work", in: doc)))
    }

    @Test func aFocusWithoutAProfileChangesNothing() {
        var doc = document()
        #expect(doc.profileForFocusChange(to: doNotDisturb) == nil)
        #expect(doc.focusSwitch == nil)
        #expect(doc.profileForFocusChange(to: nil) == nil)
    }

    @Test func focusEndingReturnsToThePreviousProfile() {
        var doc = document()
        doc.activateProfile(doc.profileForFocusChange(to: work)!)
        #expect(doc.profileForFocusChange(to: nil) == id("Home", in: doc))
        #expect(doc.focusSwitch == nil)
    }

    @Test func focusEndingCanStay() {
        var doc = document(whenFocusEnds: .stay)
        doc.activateProfile(doc.profileForFocusChange(to: work)!)
        #expect(doc.profileForFocusChange(to: nil) == nil)
        #expect(doc.focusSwitch == nil)
        #expect(doc.activeProfileID == id("Work", in: doc))
    }

    @Test func theSameFocusAgainChangesNothing() {
        var doc = document()
        doc.activateProfile(doc.profileForFocusChange(to: work)!)
        let bookkeeping = doc.focusSwitch
        #expect(doc.profileForFocusChange(to: work) == nil)
        #expect(doc.focusSwitch == bookkeeping)
    }

    @Test func switchingBetweenTwoFocusesKeepsTheOriginalPreviousProfile() {
        var doc = document()
        doc.activateProfile(doc.profileForFocusChange(to: work)!)
        let play = doc.profileForFocusChange(to: sleep)
        #expect(play == id("Play", in: doc))
        doc.activateProfile(play!)
        #expect(doc.focusSwitch?.previousProfileID == id("Home", in: doc))
        #expect(doc.profileForFocusChange(to: nil) == id("Home", in: doc))
    }

    @Test func aFocusWithoutAProfileAfterOneWithALeavesItsProfileUntilFocusEnds() {
        var doc = document()
        doc.activateProfile(doc.profileForFocusChange(to: work)!)
        #expect(doc.profileForFocusChange(to: doNotDisturb) == nil)
        #expect(doc.activeProfileID == id("Work", in: doc))
        #expect(doc.profileForFocusChange(to: nil) == id("Home", in: doc))
    }

    @Test func theUsersOwnChoiceDuringAFocusStands() {
        var doc = document()
        doc.activateProfile(doc.profileForFocusChange(to: work)!)
        doc.activateProfile(id("Play", in: doc))
        #expect(doc.profileForFocusChange(to: nil) == nil)
        #expect(doc.activeProfileID == id("Play", in: doc))
        #expect(doc.focusSwitch == nil)
    }

    @Test func aLaterFocusComesBackToTheUsersOwnChoice() {
        var doc = document()
        doc.activateProfile(doc.profileForFocusChange(to: work)!)
        doc.activateProfile(id("Play", in: doc))
        // Sleep shows Play, which is already showing: nothing to switch, but the bookkeeping updates.
        #expect(doc.profileForFocusChange(to: sleep) == nil)
        #expect(
            doc.focusSwitch
                == FocusProfileSwitch(previousProfileID: id("Play", in: doc), focusProfileID: id("Play", in: doc)))
        #expect(doc.profileForFocusChange(to: nil) == nil)

        doc = document()
        doc.activateProfile(doc.profileForFocusChange(to: sleep)!)
        doc.activateProfile(id("Home", in: doc))
        doc.activateProfile(doc.profileForFocusChange(to: work)!)
        #expect(doc.profileForFocusChange(to: nil) == id("Home", in: doc))
    }

    @Test func aFocusWhoseProfileIsAlreadyShowingSwitchesNothingButStillReturns() {
        var doc = document()
        doc.activateProfile(id("Work", in: doc))
        #expect(doc.profileForFocusChange(to: work) == nil)
        #expect(doc.profileForFocusChange(to: nil) == nil)
        #expect(doc.focusSwitch == nil)
    }

    @Test func aDeletedProfileNoLongerSwitches() {
        var doc = document()
        doc.deleteProfile(id("Work", in: doc))
        #expect(doc.settings.focusRules.profile(for: work) == nil)
        #expect(doc.settings.focusRules.profile(for: sleep) == id("Play", in: doc))
        #expect(doc.profileForFocusChange(to: work) == nil)
    }

    @Test func deletingAProfileInvolvedInAFocusSwitchForgetsTheSwitch() {
        var doc = document()
        doc.activateProfile(doc.profileForFocusChange(to: work)!)
        doc.deleteProfile(id("Home", in: doc))
        #expect(doc.focusSwitch == nil)
        #expect(doc.profileForFocusChange(to: nil) == nil)
    }

    @Test func focusEndingWithAStaleBookkeepingIsHarmless() {
        var doc = document()
        doc.focusSwitch = FocusProfileSwitch(previousProfileID: UUID(), focusProfileID: doc.activeProfileID)
        #expect(doc.profileForFocusChange(to: nil) == nil)
        #expect(doc.focusSwitch == nil)
    }

    @Test func rulesDecodeTolerantly() throws {
        let json = #"""
            {"profileByMode": {"com.apple.focus.work": "6F0C9E4B-2B57-4C1F-9C55-3C7A8E1D0A01", "bad": "nope"},
             "whenFocusEnds": "sometimes"}
            """#
        let rules = try JSONDecoder().decode(FocusProfileRules.self, from: Data(json.utf8))
        #expect(
            rules.profileByMode == ["com.apple.focus.work": UUID(uuidString: "6F0C9E4B-2B57-4C1F-9C55-3C7A8E1D0A01")!])
        #expect(rules.whenFocusEnds == .returnToPrevious)

        let garbage = try JSONDecoder().decode(FocusProfileRules.self, from: Data(#"{"profileByMode": 3}"#.utf8))
        #expect(garbage == .default)

        let settings = try JSONDecoder().decode(DockSettings.self, from: Data(#"{"focusRules": "none"}"#.utf8))
        #expect(settings.focusRules == .default)
    }

    @Test func rulesAndBookkeepingRoundTripThroughTheFile() throws {
        var doc = document()
        doc.activateProfile(doc.profileForFocusChange(to: work)!)
        let decoded = try DockStorage.decode(DockStorage.encode(doc))
        #expect(decoded == doc)
        #expect(decoded.settings.focusRules == doc.settings.focusRules)
        #expect(decoded.focusSwitch == doc.focusSwitch)
    }

    @Test func aFileWithoutFocusKeysLoadsWithDefaults() throws {
        let profile = DockProfile(name: "Only")
        var doc = DockDocument(profiles: [profile], activeProfileID: profile.id)
        doc.settings.focusRules.setProfile(profile.id, for: work)
        var json = try JSONSerialization.jsonObject(with: DockStorage.encode(doc)) as! [String: Any]
        var settings = json["settings"] as! [String: Any]
        settings["focusRules"] = nil
        json["settings"] = settings
        json["focusSwitch"] = ["previousProfileID": 1]
        let decoded = try DockStorage.decode(JSONSerialization.data(withJSONObject: json))
        #expect(decoded.settings.focusRules == .default)
        #expect(decoded.focusSwitch == nil)
    }
}

@Suite("Focus modes in DockStore")
@MainActor
struct FocusProfileStoreTests {
    private func store() -> DockStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("opendock-tests-\(UUID().uuidString)", isDirectory: true)
        let storage = DockStorage(fileURL: dir.appendingPathComponent("dock.json"))
        return DockStore(storage: storage, document: .firstRun(), saveDelay: .zero)
    }

    @Test func settingAFocusProfilePersistsAndNoOpsAreFree() {
        let store = store()
        let work = store.addProfile(named: "Work")
        store.setFocusProfile(work, for: "com.apple.focus.work")
        #expect(store.settings.focusRules.profile(for: "com.apple.focus.work") == work)

        let before = store.document
        store.setFocusProfile(work, for: "com.apple.focus.work")
        #expect(store.document == before)

        store.setFocusProfile(nil, for: "com.apple.focus.work")
        #expect(store.settings.focusRules.profileByMode.isEmpty)
    }

    @Test func focusChangesGoThroughTheStore() {
        let store = store()
        let home = store.activeProfileID
        let work = store.addProfile(named: "Work")
        store.setFocusProfile(work, for: "com.apple.focus.work")

        let target = store.profileForFocusChange(to: "com.apple.focus.work")
        #expect(target == work)
        #expect(store.document.focusSwitch?.previousProfileID == home)
        store.selectProfile(work)

        let before = store.document
        #expect(store.profileForFocusChange(to: "com.apple.focus.work") == nil)
        #expect(store.document == before)

        #expect(store.profileForFocusChange(to: nil) == home)
        #expect(store.document.focusSwitch == nil)
    }
}
