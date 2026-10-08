import Foundation

/// How macOS Focus modes drive the active profile: the profile each Focus shows, and what
/// happens when Focus turns off. Focus modes are identified by the system's mode identifier
/// (`com.apple.focus.work`, say), which survives renaming the Focus.
public struct FocusProfileRules: Hashable, Codable, Sendable {
    public enum FocusEnd: String, Codable, Sendable, CaseIterable {
        /// Go back to the profile that was showing before a Focus switched it.
        case returnToPrevious
        /// Keep showing the Focus's profile.
        case stay
    }

    /// The profile to show while each Focus is on, by mode identifier. A Focus with no entry,
    /// or whose profile has since been deleted, leaves the dock as it is.
    public var profileByMode: [String: DockProfile.ID]
    public var whenFocusEnds: FocusEnd

    public init(profileByMode: [String: DockProfile.ID] = [:], whenFocusEnds: FocusEnd = .returnToPrevious) {
        self.profileByMode = profileByMode
        self.whenFocusEnds = whenFocusEnds
    }

    public static let `default` = FocusProfileRules()

    public func profile(for mode: String) -> DockProfile.ID? {
        profileByMode[mode]
    }

    /// `nil` means the Focus doesn't change the profile.
    public mutating func setProfile(_ id: DockProfile.ID?, for mode: String) {
        profileByMode[mode] = id
    }
}

// MARK: - Tolerant decoding

extension FocusProfileRules {
    /// Missing or malformed keys fall back to the defaults; an entry whose profile ID isn't a
    /// UUID is skipped on its own, so one bad entry doesn't drop the others.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? c.decodeIfPresent([String: String].self, forKey: .profileByMode)) ?? [:]
        profileByMode = raw.reduce(into: [:]) { result, entry in
            if let id = UUID(uuidString: entry.value) { result[entry.key] = id }
        }
        whenFocusEnds = (try? c.decodeIfPresent(FocusEnd.self, forKey: .whenFocusEnds)) ?? .returnToPrevious
    }
}

/// Bookkeeping while a Focus has switched the profile: what was showing before, and what the
/// Focus picked, so Focus ending can put the earlier profile back unless the user has chosen
/// another profile themselves in the meantime. Persisted with the document, so quitting
/// OpenDock during a Focus doesn't lose it.
public struct FocusProfileSwitch: Hashable, Codable, Sendable {
    public var previousProfileID: DockProfile.ID
    public var focusProfileID: DockProfile.ID

    public init(previousProfileID: DockProfile.ID, focusProfileID: DockProfile.ID) {
        self.previousProfileID = previousProfileID
        self.focusProfileID = focusProfileID
    }
}

// MARK: - Applying Focus changes

public extension DockDocument {
    /// Applies a change of the active Focus. `mode` is the identifier of the Focus that's now
    /// on, or nil when every Focus is off. Returns the profile the dock should switch to, or
    /// nil to leave it alone. Call it once per change; calling it again with the same Focus
    /// changes nothing.
    ///
    /// A Focus with a profile switches to it and remembers what was showing, so the end of
    /// Focus can bring it back (with `FocusProfileRules.FocusEnd.returnToPrevious`). A Focus
    /// without one leaves the dock alone, including a profile an earlier Focus chose. When
    /// the user picks another profile themselves while a Focus is on, that choice stands: the
    /// end of Focus doesn't undo it, and a later Focus comes back to it.
    mutating func profileForFocusChange(to mode: String?) -> DockProfile.ID? {
        guard let mode else { return profileForFocusEnd() }
        guard let target = settings.focusRules.profile(for: mode), profile(id: target) != nil else { return nil }

        let previous: DockProfile.ID
        if let current = focusSwitch, current.focusProfileID == activeProfileID,
            profile(id: current.previousProfileID) != nil
        {
            previous = current.previousProfileID
        } else {
            previous = activeProfileID
        }
        focusSwitch = FocusProfileSwitch(previousProfileID: previous, focusProfileID: target)
        return target == activeProfileID ? nil : target
    }

    private mutating func profileForFocusEnd() -> DockProfile.ID? {
        guard let current = focusSwitch else { return nil }
        focusSwitch = nil
        guard settings.focusRules.whenFocusEnds == .returnToPrevious,
            current.focusProfileID == activeProfileID,
            current.previousProfileID != activeProfileID,
            profile(id: current.previousProfileID) != nil
        else { return nil }
        return current.previousProfileID
    }
}
