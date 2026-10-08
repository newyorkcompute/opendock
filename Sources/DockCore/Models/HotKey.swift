import Foundation

/// A system-wide keyboard shortcut. The key is a virtual key code, so the shortcut stays on
/// the same physical key whatever the keyboard layout.
public struct HotKey: Hashable, Codable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)
    }

    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Global shortcuts need ⌘ or ⌃. Without either they'd swallow ordinary typing, and
    /// macOS 15 and later refuse ones that use only ⌥ or ⌥⇧.
    public var isValidGlobalShortcut: Bool {
        !modifiers.isDisjoint(with: [.command, .control])
    }

    /// The modifiers as menus show them, in Apple's order: ⌃⌥⇧⌘.
    public var modifierSymbols: String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols
    }
}
