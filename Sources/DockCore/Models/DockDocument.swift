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
    /// `DockProfile` skips kinds it doesn't know rather than rejecting the file. Neither do
    /// new settings or top-level fields (such as `recentApps`), which decode with defaults,
    /// so older builds can still open the file.
    public static let currentVersion = 2

    public var version: Int
    public var profiles: [DockProfile]
    public var activeProfileID: DockProfile.ID
    public var settings: DockSettings
    /// Whether the welcome window has been shown and closed. Only a fresh install starts
    /// without it; a file saved before the welcome window existed decodes as seen.
    public var hasSeenWelcome: Bool
    /// The apps used most recently, for the recent apps section. Shared by all profiles:
    /// they're about what the user did, not about a layout.
    public var recentApps: RecentApps
    /// Set while a Focus mode has switched the profile; nil otherwise. See `FocusProfileSwitch`.
    public var focusSwitch: FocusProfileSwitch?

    public init(
        version: Int = DockDocument.currentVersion,
        profiles: [DockProfile],
        activeProfileID: DockProfile.ID,
        settings: DockSettings = .default,
        hasSeenWelcome: Bool = true,
        recentApps: RecentApps = RecentApps(),
        focusSwitch: FocusProfileSwitch? = nil
    ) {
        precondition(!profiles.isEmpty, "A document needs at least one profile")
        self.version = version
        self.profiles = profiles
        self.activeProfileID = profiles.contains { $0.id == activeProfileID } ? activeProfileID : profiles[0].id
        self.settings = settings
        self.hasSeenWelcome = hasSeenWelcome
        self.recentApps = recentApps
        self.focusSwitch = focusSwitch
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

// MARK: - Tolerant decoding

extension DockDocument {
    /// A missing or unknown active profile falls back to the first one, and a profile that
    /// repeats another's ID gets a new one, so every profile can be told apart. A file with
    /// no profiles at all is rejected (and backed up by `DockStore`) rather than crashing.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        var profiles = try c.decode([DockProfile].self, forKey: .profiles)
        guard !profiles.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .profiles, in: c, debugDescription: "A document needs at least one profile")
        }
        var seen = Set<DockProfile.ID>()
        for index in profiles.indices where !seen.insert(profiles[index].id).inserted {
            profiles[index].id = UUID()
        }
        self.profiles = profiles
        let active = try? c.decodeIfPresent(DockProfile.ID.self, forKey: .activeProfileID)
        activeProfileID = active.flatMap { id in profiles.contains { $0.id == id } ? id : nil } ?? profiles[0].id
        settings = try c.decodeIfPresent(DockSettings.self, forKey: .settings) ?? .default
        hasSeenWelcome = (try? c.decodeIfPresent(Bool.self, forKey: .hasSeenWelcome)) ?? true
        recentApps = (try? c.decodeIfPresent(RecentApps.self, forKey: .recentApps)) ?? RecentApps()
        focusSwitch = try? c.decodeIfPresent(FocusProfileSwitch.self, forKey: .focusSwitch)
    }
}

// MARK: - Profiles

public extension DockDocument {
    func profile(id: DockProfile.ID) -> DockProfile? {
        profiles.first { $0.id == id }
    }

    /// The profile `offset` steps after the active one, wrapping around at either end.
    func profileID(offsetFromActive offset: Int) -> DockProfile.ID {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return profiles[0].id }
        let count = profiles.count
        return profiles[((index + offset) % count + count) % count].id
    }

    mutating func activateProfile(_ id: DockProfile.ID) {
        guard profile(id: id) != nil else { return }
        activeProfileID = id
    }

    /// Adds an empty profile at the end, with a name no other profile has. It isn't activated.
    @discardableResult
    mutating func addProfile(named name: String? = nil) -> DockProfile.ID {
        let requested = name.flatMap(Self.trimmedName)
        let profile = DockProfile(
            name: requested.map { uniqueProfileName($0, numberFirst: false) }
                ?? uniqueProfileName("Profile", numberFirst: true))
        profiles.append(profile)
        return profile.id
    }

    /// Copies a profile, right after the original. The copy's items get new IDs, so the two
    /// layouts never share an item. It isn't activated.
    @discardableResult
    mutating func duplicateProfile(_ id: DockProfile.ID) -> DockProfile.ID? {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return nil }
        let source = profiles[index]
        let copy = DockProfile(
            name: uniqueProfileName("\(source.name) Copy", numberFirst: false),
            items: source.items.map { DockItem(kind: $0.kind) }
        )
        profiles.insert(copy, at: index + 1)
        return copy.id
    }

    /// Blank names are ignored. Names don't have to be unique; IDs tell profiles apart.
    mutating func renameProfile(_ id: DockProfile.ID, to name: String) {
        guard let name = Self.trimmedName(name),
            let index = profiles.firstIndex(where: { $0.id == id })
        else { return }
        profiles[index].name = name
    }

    /// Deletes a profile unless it's the only one. Deleting the active profile activates the
    /// one after it (or before it, if it was last). Focus modes that showed the profile stop
    /// changing the profile. Returns whether anything was deleted.
    @discardableResult
    mutating func deleteProfile(_ id: DockProfile.ID) -> Bool {
        guard profiles.count > 1, let index = profiles.firstIndex(where: { $0.id == id }) else { return false }
        if id == activeProfileID {
            activeProfileID = profiles[index + 1 < profiles.count ? index + 1 : index - 1].id
        }
        profiles.remove(at: index)
        settings.focusRules.profileByMode = settings.focusRules.profileByMode.filter { $0.value != id }
        if let focusSwitch, focusSwitch.focusProfileID == id || focusSwitch.previousProfileID == id {
            self.focusSwitch = nil
        }
        return true
    }

    /// Moves a profile `offset` places along the list (the order profiles are cycled in),
    /// stopping at either end.
    mutating func moveProfile(_ id: DockProfile.ID, by offset: Int) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        let destination = min(max(index + offset, 0), profiles.count - 1)
        guard destination != index else { return }
        profiles.insert(profiles.remove(at: index), at: destination)
    }

    /// A name no profile has yet. With `numberFirst` it's always numbered, starting from the
    /// new profile's position ("Profile 2" for the second); otherwise it's `base` if that's
    /// free, then "base 2", "base 3"…
    func uniqueProfileName(_ base: String, numberFirst: Bool) -> String {
        let taken = Set(profiles.map(\.name))
        if !numberFirst, !taken.contains(base) { return base }
        var number = numberFirst ? profiles.count + 1 : 2
        while taken.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    private static func trimmedName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Widgets

public extension DockDocument {
    /// Runs `body` over every widget instance in every profile, in place.
    mutating func updateWidgets(_ body: (inout WidgetInstance) -> Void) {
        for profileIndex in profiles.indices {
            for itemIndex in profiles[profileIndex].items.indices {
                guard case var .widget(instance) = profiles[profileIndex].items[itemIndex].kind else { continue }
                body(&instance)
                profiles[profileIndex].items[itemIndex].kind = .widget(instance)
            }
        }
    }

    /// Replaces every widget setting that isn't valid for its key (per the widget's schema
    /// in `schemas`, by type ID) with the key's default. Widgets without a schema, and keys
    /// a schema doesn't declare, are left as they are. Returns how many values changed.
    @discardableResult
    mutating func sanitizeWidgetSettings(using schemas: [String: WidgetSettingsSchema]) -> Int {
        guard !schemas.isEmpty else { return 0 }
        var changed = 0
        updateWidgets { instance in
            guard let schema = schemas[instance.typeID] else { return }
            for key in schema.invalidKeys(in: instance.settings) {
                instance.settings[key.name] = key.defaultValue
                changed += 1
            }
        }
        return changed
    }
}

// MARK: - Defaults

public extension DockDocument {
    /// What a fresh install gets: a handful of common apps, the three built-in widgets,
    /// then Downloads and the Trash, with dividers between the groups, so the dock is
    /// useful before the user touches anything. Only used when there's no `dock.json`;
    /// existing layouts are never rewritten to match (Settings > Dock Items can add the
    /// Trash to one).
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
        items.append(.trash())

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
    public static let systemActivity = "com.newyorkcompute.opendock.widget.systemactivity"
    public static let weather = "com.newyorkcompute.opendock.widget.weather"
    public static let nowPlaying = "com.newyorkcompute.opendock.widget.nowplaying"
    public static let timeProgress = "com.newyorkcompute.opendock.widget.timeprogress"
}
