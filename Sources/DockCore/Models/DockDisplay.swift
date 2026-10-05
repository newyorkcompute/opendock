import Foundation

extension DockSettings {
    /// Which display the dock lives on.
    public enum Display: Hashable, Sendable {
        /// The main display, the one with the menu bar (System Settings > Displays).
        case main
        /// The display with the active menu bar: follows keyboard focus between displays
        /// when "Displays have separate Spaces" is on.
        case active
        /// A particular display, by its CoreGraphics display UUID, which survives
        /// unplugging and rearranging. `name` is only for showing the choice while the
        /// display is disconnected; the dock uses the main display until it comes back.
        case specific(id: String, name: String)
    }
}

// MARK: - Codable

/// Stored as `{"kind": "main"}`, `{"kind": "active"}` or
/// `{"kind": "specific", "id": "<UUID>", "name": "<name>"}`. Anything unrecognized
/// decodes as `.main`, so a newer or damaged value never invalidates the settings.
extension DockSettings.Display: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, id, name
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        switch kind {
        case "active":
            self = .active
        case "specific":
            if let id = try? c.decodeIfPresent(String.self, forKey: .id), !id.isEmpty {
                let name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
                self = .specific(id: id, name: name)
            } else {
                self = .main
            }
        default:
            self = .main
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .main:
            try c.encode("main", forKey: .kind)
        case .active:
            try c.encode("active", forKey: .kind)
        case let .specific(id, name):
            try c.encode("specific", forKey: .kind)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
        }
    }
}
