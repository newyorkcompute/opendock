import AppKit
import SwiftUI

/// The borderless, non-activating window that hosts the dock.
///
/// Non-activating is the whole trick: clicking an icon must launch the app
/// without stealing focus from whatever the user is working in, exactly like
/// Apple's Dock.
final class DockPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        // No `.fullScreenAuxiliary` by default: the dock stays off full-screen Spaces so it
        // never covers a video or presentation. `DockController+FullScreen.swift` adds it
        // while the pointer, held at the edge, has called the dock up over one.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // the content draws its own shadow so it follows the rounded shape
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isExcludedFromWindowsMenu = true
        tabbingMode = .disallowed
    }

    // Allow key status so popovers and text fields inside widgets can take input,
    // but never become main: that would make us look like a document window.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that reacts to the first click even when the panel isn't key.
final class DockHostingView<Content: View>: NSHostingView<Content> {
    /// Receives every drop on the dock: reordering and files from Finder. Done here
    /// rather than with SwiftUI drop destinations because those claim drags of the other
    /// type (a `String` target takes file drags, a `URL` target takes reorder drags) and
    /// then fail to load them, depending on exactly where the drop lands.
    weak var dropHandler: DockController?

    // Must stay explicit and nonisolated. Under main-actor default isolation the implicit
    // deinit of a generic class is an isolated deinit, and Swift 6.3.3 (Xcode 26)
    // segfaults in the SIL inliner on that with `-O`.
    deinit {}

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropHandler?.dragUpdated(sender) ?? []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropHandler?.dragUpdated(sender) ?? []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        dropHandler?.dragExited()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        dropHandler?.performDrop(sender) ?? false
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        dropHandler?.dragEnded()
    }
}
