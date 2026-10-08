import AppKit
import DockCore

/// Showing the dock over full-screen apps.
///
/// The panel joins every regular Space but no full-screen one, so a video or presentation
/// is never covered. Like Apple's Dock, it can still be called up there: holding the
/// pointer at the screen edge for `EdgeHold.duration` makes the panel join the full-screen
/// Space (`.fullScreenAuxiliary`) and slide in; it hides again, and leaves the Space, once
/// the pointer has left, whether or not auto-hide is on.
extension DockController {
    /// Whether the active Space on the dock's display belongs to a full-screen app. While
    /// the panel hasn't joined one on purpose, the only Space it can't be on is one of those.
    var isOnFullScreenSpace: Bool {
        guard let panel, !isRevealedOverFullScreen else { return false }
        return !panel.isOnActiveSpace
    }

    /// Called by the root view's `onChange(of: settings.revealInFullScreen)`.
    func fullScreenRevealSettingChanged() {
        if !store.settings.revealInFullScreen {
            cancelEdgeHold()
            if isRevealedOverFullScreen { hide() }
        }
        updateEdgeMonitors()
    }

    // MARK: - Holding the pointer at the edge

    /// Feed the hold with where the pointer is; `atEdge` is only true on a full-screen Space.
    func edgeHoldChanged(atEdge: Bool) {
        guard atEdge || edgeHold.isHolding else { return }
        switch edgeHold.pointerMoved(atEdge: atEdge, now: ProcessInfo.processInfo.systemUptime) {
        case .began:
            edgeHoldTask?.cancel()
            edgeHoldTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(EdgeHold.duration))
                guard !Task.isCancelled, let self else { return }
                edgeHoldElapsed()
            }
        case .ended:
            edgeHoldTask?.cancel()
            edgeHoldTask = nil
        case .none:
            break
        }
    }

    private func edgeHoldElapsed() {
        defer { edgeHold.reset() }
        // Re-check the pointer: it may have left without a move event reaching us.
        guard let screen = targetScreen,
            DockPlacement.isAtRevealEdge(NSEvent.mouseLocation, of: screen.frame, edge: edge),
            edgeHold.isComplete(now: ProcessInfo.processInfo.systemUptime),
            store.settings.revealInFullScreen, isOnFullScreenSpace
        else { return }
        revealOverFullScreen()
    }

    func cancelEdgeHold() {
        edgeHoldTask?.cancel()
        edgeHoldTask = nil
        edgeHold.reset()
    }

    // MARK: - Joining and leaving the full-screen Space

    func revealOverFullScreen() {
        guard let panel, !isRevealedOverFullScreen else { return }
        isRevealedOverFullScreen = true
        panel.collectionBehavior.insert(.fullScreenAuxiliary)
        if shellState.isVisible {
            // Auto-hide is off: the panel sits at its shown frame, which this Space never
            // displayed. Start from hidden so it slides in like an auto-hidden dock.
            shellState.isVisible = false
            panel.orderOut(nil)
        }
        reveal()
    }

    /// Take the panel back off the full-screen Space, if it had joined one, and put the dock
    /// back where the auto-hide setting wants it: off screen, or shown on the regular Spaces.
    /// Not animated; it's called once the dock has slid out or the Space has changed.
    func endFullScreenReveal() {
        guard isRevealedOverFullScreen, let panel else { return }
        isRevealedOverFullScreen = false
        panel.collectionBehavior.remove(.fullScreenAuxiliary)
        cancelScheduledHide()
        resetMagnification()
        if store.settings.autoHide {
            shellState.isVisible = false
            panel.orderOut(nil)
        } else {
            shellState.isVisible = true
            panel.alphaValue = 1
            applyFrame(animated: false)
            panel.orderFrontRegardless()
        }
    }

    func observeSpaces() {
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.activeSpaceChanged() }
        }
    }

    /// The dock revealed over a full-screen Space goes away with that Space, so leaving it
    /// (or swiping to another full-screen app) must not carry the panel along. And an
    /// auto-hidden dock that was out when a full-screen Space arrived can't be seen there;
    /// hide it so the edge hold can bring it back.
    private func activeSpaceChanged() {
        cancelEdgeHold()
        if isRevealedOverFullScreen {
            endFullScreenReveal()
        } else if store.settings.autoHide, shellState.isVisible, isOnFullScreenSpace {
            hide()
        }
    }
}
