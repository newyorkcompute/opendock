import Carbon.HIToolbox
import DockCore
import Foundation

/// Spells a `HotKey` the way menus do, such as "⌃⌥⌘→" or "⇧⌘P". Letters and symbols come
/// from the current keyboard layout (an ASCII-capable one), so a key reads as it's labeled.
@MainActor
public enum HotKeyFormatter {
    public static func string(for hotKey: HotKey) -> String {
        hotKey.modifierSymbols + keyName(hotKey.keyCode)
    }

    /// "Control Option Command Right Arrow", for VoiceOver. The menu string uses glyphs
    /// ("⌃⌥⌘→") which VoiceOver reads poorly.
    public static func spokenString(for hotKey: HotKey) -> String {
        (spokenModifiers(hotKey.modifiers) + [spokenKeyName(hotKey.keyCode)]).joined(separator: " ")
    }

    public static func spokenModifiers(_ modifiers: HotKey.Modifiers) -> [String] {
        var names: [String] = []
        if modifiers.contains(.control) { names.append("Control") }
        if modifiers.contains(.option) { names.append("Option") }
        if modifiers.contains(.shift) { names.append("Shift") }
        if modifiers.contains(.command) { names.append("Command") }
        return names
    }

    /// A key's spoken name. Arrows and editing keys are words; letters stay the character
    /// `keyName` gets from the keyboard layout.
    public static func spokenKeyName(_ keyCode: UInt16) -> String {
        if let name = spokenSpecialKeys[Int(keyCode)] { return name }
        return keyName(keyCode)
    }

    private static let spokenSpecialKeys: [Int: String] = [
        kVK_Return: "Return", kVK_ANSI_KeypadEnter: "Enter", kVK_Tab: "Tab", kVK_Space: "Space",
        kVK_Delete: "Delete", kVK_ForwardDelete: "Forward Delete", kVK_Escape: "Escape",
        kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "Page Up", kVK_PageDown: "Page Down",
        kVK_LeftArrow: "Left Arrow", kVK_RightArrow: "Right Arrow", kVK_DownArrow: "Down Arrow",
        kVK_UpArrow: "Up Arrow",
    ]

    public static func keyName(_ keyCode: UInt16) -> String {
        if let name = specialKeys[Int(keyCode)] { return name }
        return translated(keyCode) ?? "Key \(keyCode)"
    }

    private static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌅", kVK_Tab: "⇥", kVK_Space: "Space",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋", kVK_Help: "Help",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
        kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    private static func translated(_ keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                4,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let name = String(utf16CodeUnits: characters, count: length).uppercased()
        return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
    }
}
