import Foundation

/// Everything OpenDock persists, in one JSON file. Also the export/import format.
public struct DockDocument: Hashable, Codable, Sendable {
    /// Bumped when the on-disk shape changes incompatibly. Readers migrate forward.
    ///
    /// - 1: initial format.
    /// - 2: built-in widget type IDs moved from `org.opendock.widget.*` to
    ///   `com.newyorkcompute.opendock.widget.*`.
    ///
    /// New item kinds (such as `divider`) don't need a bump: they need no migration, and
    /// `DockProfile` skips kinds it doesn't know rather than rejecting the file.
    public static let currentVersion = 2

    public var version: Int
    public var profiles: [DockProfile]
    public var activeProfileID: DockProfile.ID
    public var settings: DockSettings

    public init(
        version: Int = DockDocument.currentVersion,
        profiles: [DockProfile],
        activeProfileID: DockProfile.ID,
        settings: DockSettings = .default
    ) {
        precondition(!profiles.isEmpty, "A document needs at least one profile")
        self.version = version
        self.profiles = profiles
        self.activeProfileID = profiles.contains { $0.id == activeProfileID } ? activeProfileID : profiles[0].id
        self.settings = settings
    }

    public var activeProfile: DockProfile {
        get { profiles.first { $0.id == activeProfileID } ?? profiles[0] }
        set {
            if let index = profiles.firstIndex(where: { $0.id == activeProfileID }) {
                profiles[index] = newValue
            } else {
                profiles[0] = newValue
            }
        }
    }
}

// MARK: - Defaults

public extension DockDocument {
    /// What a fresh install gets: a handful of common apps, the three built-in widgets,
    /// and Downloads, with dividers between the groups, so the dock is useful before the
    /// user touches anything. Only used when there's no `dock.json`; existing layouts are
    /// never rewritten to match.
    static func firstRun(fileManager: FileManager = .default) -> DockDocument {
        var items: [DockItem] = []

        let candidateApps = [
            "/System/Library/CoreServices/Finder.app",
            "/Applications/Safari.app",
            "/System/Applications/Mail.app",
            "/System/Applications/Messages.app",
            "/System/Applications/Calendar.app",
            "/System/Applications/Notes.app",
            "/System/Applications/Music.app",
            "/System/Applications/System Settings.app",
        ]
        for path in candidateApps where fileManager.fileExists(atPath: path) {
            items.append(.app(at: URL(fileURLWithPath: path)))
        }

        items.append(.divider())
        items.append(.widget(BuiltInWidgetID.calendar))
        items.append(.widget(BuiltInWidgetID.clock))
        items.append(.widget(BuiltInWidgetID.battery))

        if let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            items.append(.divider())
            items.append(.folder(at: downloads))
        }

        let profile = DockProfile(name: "Default", items: items)
        return DockDocument(profiles: [profile], activeProfileID: profile.id)
    }
}

/// Type IDs of the widgets that ship with OpenDock. Kept in DockCore so the
/// default layout can reference them without depending on the widget targets.
///
/// These are persisted in `dock.json`; never rename them without a `DockStorage` migration.
public enum BuiltInWidgetID {
    public static let clock = "com.newyorkcompute.opendock.widget.clock"
    public static let battery = "com.newyorkcompute.opendock.widget.battery"
    public static let calendar = "com.newyorkcompute.opendock.widget.calendar"
}
