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
        // No `.fullScreenAuxiliary`: the dock stays off full-screen Spaces so it never
        // covers a video or presentation. Edge-reveal in full screen can come later.
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
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
