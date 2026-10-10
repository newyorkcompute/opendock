import Foundation

/// Spoken values for dock items. The views apply these; the words live here so they can
/// be tested without a screen.
public enum DockItemAccessibility: Sendable {
    /// Value for an app tile. "Missing" and "Running" are words, because the question
    /// mark and the dot under the icon are the only other cues. A badge is included
    /// when the icon has one.
    public static func appValue(exists: Bool, isRunning: Bool, badge: String?) -> String {
        var parts: [String] = []
        if !exists {
            parts.append("Missing")
        } else if isRunning {
            parts.append("Running")
        }
        if let badge = badge?.trimmingCharacters(in: .whitespacesAndNewlines), !badge.isEmpty {
            parts.append(badge)
        }
        return parts.joined(separator: ", ")
    }
}
