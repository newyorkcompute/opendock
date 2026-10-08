import Foundation
import Testing

@testable import DockCore

@Suite("Keyboard navigation")
struct KeyboardNavigationTests {
    private typealias Navigation = DockKeyboardNavigation<String>
    private typealias Key = Navigation.Key

    private let row = ["finder", "safari", "mail", "downloads", "clock"]

    @Test func beginSelectsTheFirstItem() {
        var navigation = Navigation()
        #expect(!navigation.isActive)
        #expect(navigation.begin(items: row) == .selected("finder", position: 1, count: 5))
        #expect(navigation.isActive)
        #expect(navigation.selectedID == "finder")
    }

    @Test func beginPrefersTheItemUnderThePointer() {
        var navigation = Navigation()
        #expect(navigation.begin(items: row, preferring: "mail") == .selected("mail", position: 3, count: 5))
        // Something that isn't in the row (a spacer, say) is ignored.
        var other = Navigation()
        #expect(other.begin(items: row, preferring: "spacer") == .selected("finder", position: 1, count: 5))
    }

    @Test func beginWithNothingToSelectIsStillASession() {
        var navigation = Navigation()
        #expect(navigation.begin(items: []) == .none)
        #expect(navigation.isActive)
        #expect(navigation.selectedID == nil)
        #expect(navigation.handle(.next, items: []) == .none)
        #expect(navigation.handle(.activate, items: []) == .none)
        #expect(navigation.handle(.escape, items: []) == .ended)
        #expect(!navigation.isActive)
    }

    @Test func nextAndPreviousWrapAround() {
        var navigation = Navigation()
        _ = navigation.begin(items: row)
        #expect(navigation.handle(.previous, items: row) == .selected("clock", position: 5, count: 5))
        #expect(navigation.handle(.next, items: row) == .selected("finder", position: 1, count: 5))
        #expect(navigation.handle(.next, items: row) == .selected("safari", position: 2, count: 5))
    }

    @Test func firstAndLast() {
        var navigation = Navigation()
        _ = navigation.begin(items: row, preferring: "mail")
        #expect(navigation.handle(.last, items: row) == .selected("clock", position: 5, count: 5))
        #expect(navigation.handle(.first, items: row) == .selected("finder", position: 1, count: 5))
    }

    @Test func actionsApplyToTheSelection() {
        var navigation = Navigation()
        _ = navigation.begin(items: row, preferring: "downloads")
        #expect(navigation.handle(.activate, items: row) == .activate("downloads"))
        #expect(navigation.handle(.secondary, items: row) == .openSecondary("downloads"))
        #expect(navigation.handle(.remove, items: row) == .offerRemoval("downloads"))
        // None of those move the selection or end the session.
        #expect(navigation.selectedID == "downloads")
        #expect(navigation.isActive)
    }

    @Test func escapeEndsTheSession() {
        var navigation = Navigation()
        _ = navigation.begin(items: row)
        #expect(navigation.handle(.escape, items: row) == .ended)
        #expect(!navigation.isActive)
        #expect(navigation.selectedID == nil)
        // Keys do nothing after that.
        #expect(navigation.handle(.next, items: row) == .none)
        #expect(navigation.end() == .none)
    }

    @Test func endingFromOutsideIsReportedOnce() {
        var navigation = Navigation()
        _ = navigation.begin(items: row)
        #expect(navigation.end() == .ended)
        #expect(navigation.end() == .none)
    }

    @Test func pointerMovesTheSelection() {
        var navigation = Navigation()
        _ = navigation.begin(items: row)
        #expect(navigation.select("mail", in: row) == .selected("mail", position: 3, count: 5))
        // Resting on the same item again changes nothing.
        #expect(navigation.select("mail", in: row) == .none)
        #expect(navigation.select("spacer", in: row) == .none)
        var inactive = Navigation()
        #expect(inactive.select("mail", in: row) == .none)
    }

    @Test func removedSelectionMovesToTheItemInItsPlace() {
        var navigation = Navigation()
        _ = navigation.begin(items: row, preferring: "mail")
        let withoutMail = ["finder", "safari", "downloads", "clock"]
        #expect(navigation.itemsChanged(withoutMail) == .selected("downloads", position: 3, count: 4))
        // Deleting the last item lands on the new last one.
        _ = navigation.handle(.last, items: withoutMail)
        #expect(
            navigation.itemsChanged(["finder", "safari", "downloads"]) == .selected("downloads", position: 3, count: 3))
        // And nothing happens while the selection is still there.
        #expect(navigation.itemsChanged(["finder", "safari", "downloads"]) == .none)
        #expect(navigation.itemsChanged([]) == .none)
        #expect(navigation.selectedID == nil)
        #expect(navigation.isActive)
    }

    @Test func keysReconcileAStaleSelection() {
        var navigation = Navigation()
        _ = navigation.begin(items: row, preferring: "safari")
        // Safari quit before the next key; the key applies to the item now in its place.
        let withoutSafari = ["finder", "mail", "downloads", "clock"]
        #expect(navigation.handle(.activate, items: withoutSafari) == .activate("mail"))
        #expect(navigation.handle(.next, items: withoutSafari) == .selected("downloads", position: 3, count: 4))
    }

    @Test func arrowsFollowTheDocksEdge() {
        #expect(Key(arrow: .right, edge: .bottom) == .next)
        #expect(Key(arrow: .left, edge: .bottom) == .previous)
        #expect(Key(arrow: .up, edge: .bottom) == nil)
        #expect(Key(arrow: .down, edge: .bottom) == nil)
        for edge in [DockSettings.Edge.left, .right] {
            #expect(Key(arrow: .down, edge: edge) == .next)
            #expect(Key(arrow: .up, edge: edge) == .previous)
            #expect(Key(arrow: .left, edge: edge) == nil)
            #expect(Key(arrow: .right, edge: edge) == nil)
        }
    }
}

@Suite("Keyboard navigation shortcut")
struct KeyboardNavigationSettingTests {
    @Test func defaultsToUnset() {
        #expect(DockSettings.default.keyboardNavigationHotKey == nil)
    }

    @Test func olderSettingsFilesStillLoad() throws {
        let json = #"{"iconSize": 56}"#
        let settings = try JSONDecoder().decode(DockSettings.self, from: Data(json.utf8))
        #expect(settings.keyboardNavigationHotKey == nil)
        #expect(settings.iconSize == 56)
    }

    @Test func badValuesFallBackToUnset() throws {
        let json = #"{"keyboardNavigationHotKey": "control-option-d"}"#
        let settings = try JSONDecoder().decode(DockSettings.self, from: Data(json.utf8))
        #expect(settings.keyboardNavigationHotKey == nil)
    }

    @Test func roundTrips() throws {
        var settings = DockSettings.default
        settings.keyboardNavigationHotKey = HotKey(keyCode: 2, modifiers: [.control, .option])
        let decoded = try JSONDecoder().decode(DockSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.keyboardNavigationHotKey == settings.keyboardNavigationHotKey)
    }

    @Test func aShortcutDoesOnlyOneThing() {
        let shortcut = HotKey(keyCode: 2, modifiers: [.control, .option])
        var settings = DockSettings.default
        settings.setHotKey(shortcut, for: \.nextProfileHotKey)
        #expect(settings.nextProfileHotKey == shortcut)

        settings.setHotKey(shortcut, for: \.keyboardNavigationHotKey)
        #expect(settings.keyboardNavigationHotKey == shortcut)
        #expect(settings.nextProfileHotKey == nil)

        // A different shortcut leaves the others alone; clearing never touches them.
        let other = HotKey(keyCode: 3, modifiers: [.command])
        settings.setHotKey(other, for: \.previousProfileHotKey)
        #expect(settings.keyboardNavigationHotKey == shortcut)
        settings.setHotKey(nil, for: \.previousProfileHotKey)
        #expect(settings.previousProfileHotKey == nil)
        #expect(settings.keyboardNavigationHotKey == shortcut)
    }
}
