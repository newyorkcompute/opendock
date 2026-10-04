import Foundation

/// Everything OpenDock persists, in one JSON file. Also the export/import format.
public struct DockDocument: Hashable, Codable, Sendable {
    /// Bumped when the on-disk shape changes incompatibly. Readers migrate forward.
    public static let currentVersion = 1

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
    /// What a fresh install gets: a handful of common apps, Downloads, and the three
    /// built-in widgets, so the dock is useful before the user touches anything.
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

        items.append(.spacer(.small))
        items.append(.widget(BuiltInWidgetID.calendar))
        items.append(.widget(BuiltInWidgetID.clock))
        items.append(.widget(BuiltInWidgetID.battery))

        if let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            items.append(.spacer(.small))
            items.append(.folder(at: downloads))
        }

        let profile = DockProfile(name: "Default", items: items)
        return DockDocument(profiles: [profile], activeProfileID: profile.id)
    }
}

/// Type IDs of the widgets that ship with OpenDock. Kept in DockCore so the
/// default layout can reference them without depending on the widget targets.
public enum BuiltInWidgetID {
    public static let clock = "org.opendock.widget.clock"
    public static let battery = "org.opendock.widget.battery"
    public static let calendar = "org.opendock.widget.calendar"
}
