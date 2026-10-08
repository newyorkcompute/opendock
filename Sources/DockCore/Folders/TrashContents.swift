import Foundation

/// What decides whether the Trash icon is shown full or empty. Pure logic; `TrashMonitor`
/// in `SystemServices` finds out what's in the Trash and keeps the dock up to date.
public enum TrashContents {
    /// Files Finder keeps in the Trash for itself. The Trash is empty when they're all
    /// that's in it, as it is in Finder and in Apple's Dock.
    public static let ignoredNames: Set<String> = [".DS_Store", ".localized"]

    /// Whether a Trash containing the items named `names` counts as empty.
    public static func isEmpty(itemNames names: some Sequence<String>) -> Bool {
        !names.contains { !ignoredNames.contains($0) }
    }

    /// The number in Finder's answer to `countScript` (a line such as `"3\n"`), or nil
    /// when the answer isn't one, as when Finder couldn't be asked.
    public static func itemCount(inFinderReply reply: String?) -> Int? {
        guard let reply else { return nil }
        return Int(reply.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// AppleScript that asks Finder how many items are in the Trash. Finder can see them
    /// even where OpenDock can't: `~/.Trash` is behind Full Disk Access.
    public static let countScript = #"tell application "Finder" to count items of trash"#

    /// AppleScript that has Finder empty the Trash. Finder asks the user to confirm first
    /// (unless they turned that warning off), so OpenDock doesn't wait for an answer: the
    /// script returns at once and Finder carries on by itself.
    public static let emptyScript = """
        ignoring application responses
            tell application "Finder"
                activate
                empty trash
            end tell
        end ignoring
        """
}
