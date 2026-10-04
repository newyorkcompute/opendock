import Foundation

/// Hooks the app layer provides to the shell for things only the app can do.
public struct DockActions {
    public var openSettings: () -> Void
    public var quit: () -> Void

    public init(openSettings: @escaping () -> Void, quit: @escaping () -> Void) {
        self.openSettings = openSettings
        self.quit = quit
    }

    public static let noop = DockActions(openSettings: {}, quit: {})
}
