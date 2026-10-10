import Foundation

/// A minimized window the dock can show as its own item, after the running and recent
/// apps and before the Trash.
///
/// `id` is the window's own id (the window number the system assigns, unique across
/// processes), so the same window stays one item however many times it's reported.
public struct MinimizedDockWindow: Identifiable, Hashable, Sendable {
    public struct ID: Hashable, Sendable {
        public var windowID: Int

        public init(windowID: Int) {
            self.windowID = windowID
        }
    }

    public var id: ID
    /// The process that owns the window, so restoring it can bring that app forward.
    public var processIdentifier: Int32
    /// Empty when the window has no title.
    public var title: String
    /// The app the window belongs to, for the icon and for the label of an untitled window.
    public var app: AppItem

    public init(id: ID, processIdentifier: Int32, title: String, app: AppItem) {
        self.id = id
        self.processIdentifier = processIdentifier
        self.title = title
        self.app = app
    }

    /// The hover label: the window's title, or the app's name when it hasn't got one.
    public var label: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? app.displayName : trimmed
    }
}

/// Which minimized windows the dock shows, and in what order. Pure bookkeeping: finding
/// the windows, and drawing them, happen elsewhere.
public enum MinimizedWindowSection {
    /// The section is in the dock when the setting is on and there is a window to show.
    /// An empty section would be a divider with nothing after it.
    public static func isVisible(showMinimizedWindows: Bool, windows: [MinimizedDockWindow]) -> Bool {
        showMinimizedWindows && !windows.isEmpty
    }

    /// The windows to show, one per window id.
    ///
    /// A window already on the dock keeps its place, so minimizing something else doesn't
    /// reshuffle the row; the latest report updates its title and app in place. Windows
    /// that are no longer minimized drop out. Newly minimized ones are appended, in the
    /// order they were first reported, so the newest sits just before the Trash. The same
    /// id reported twice is kept once.
    public static func ordered(
        reported: [MinimizedDockWindow],
        previouslyShown: [MinimizedDockWindow] = []
    ) -> [MinimizedDockWindow] {
        var latest: [MinimizedDockWindow.ID: MinimizedDockWindow] = [:]
        var firstIndex: [MinimizedDockWindow.ID: Int] = [:]
        for (index, window) in reported.enumerated() {
            if firstIndex[window.id] == nil { firstIndex[window.id] = index }
            latest[window.id] = window
        }

        var result: [MinimizedDockWindow] = []
        var placed: Set<MinimizedDockWindow.ID> = []
        for previous in previouslyShown {
            guard let window = latest[previous.id], placed.insert(previous.id).inserted else { continue }
            result.append(window)
        }
        let newcomers = firstIndex.sorted { $0.value < $1.value }.map(\.key)
        for id in newcomers {
            guard let window = latest[id], placed.insert(id).inserted else { continue }
            result.append(window)
        }
        return result
    }

    /// None when the setting is off, otherwise `ordered`. Turning the section off hides
    /// every window; it doesn't remember a place for them.
    public static func displayed(
        reported: [MinimizedDockWindow],
        previouslyShown: [MinimizedDockWindow] = [],
        showMinimizedWindows: Bool
    ) -> [MinimizedDockWindow] {
        guard showMinimizedWindows else { return [] }
        return ordered(reported: reported, previouslyShown: previouslyShown)
    }
}
