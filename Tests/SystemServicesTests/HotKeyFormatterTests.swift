import Carbon.HIToolbox
import DockCore
import Testing

@testable import SystemServices

@MainActor
@Suite("Spoken shortcut names")
struct HotKeyFormatterTests {
    @Test func modifiersAreWordsInMenuOrder() {
        let hotKey = HotKey(
            keyCode: UInt16(kVK_RightArrow), modifiers: [.control, .option, .shift, .command])
        #expect(
            HotKeyFormatter.spokenString(for: hotKey) == "Control Option Shift Command Right Arrow")
    }

    @Test func arrowsAndEditingKeysAreWords() {
        #expect(HotKeyFormatter.spokenKeyName(UInt16(kVK_LeftArrow)) == "Left Arrow")
        #expect(HotKeyFormatter.spokenKeyName(UInt16(kVK_UpArrow)) == "Up Arrow")
        #expect(HotKeyFormatter.spokenKeyName(UInt16(kVK_Delete)) == "Delete")
        #expect(HotKeyFormatter.spokenKeyName(UInt16(kVK_Escape)) == "Escape")
        #expect(HotKeyFormatter.spokenKeyName(UInt16(kVK_Return)) == "Return")
    }

    @Test func aShortcutWithNoExtraModifiersStillNamesTheKey() {
        let hotKey = HotKey(keyCode: UInt16(kVK_Space), modifiers: [.command])
        #expect(HotKeyFormatter.spokenString(for: hotKey) == "Command Space")
    }
}
