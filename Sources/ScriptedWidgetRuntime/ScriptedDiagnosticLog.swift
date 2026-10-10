import Foundation

/// One line in the scripted-widget error log Settings shows.
public struct ScriptedDiagnostic: Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var date = Date()
    public var message: String
}

/// A short ring buffer of install and script errors. Newest last. Over the cap, the oldest
/// lines go.
public struct ScriptedDiagnosticLog: Equatable, Sendable {
    public static let capacity = 50

    public private(set) var entries: [ScriptedDiagnostic]

    public init(entries: [ScriptedDiagnostic] = []) {
        self.entries = entries
    }

    public mutating func record(_ message: String, at date: Date = .now) {
        entries.append(ScriptedDiagnostic(date: date, message: message))
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
    }
}
