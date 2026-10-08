import AppKit
import DockCore
import SwiftUI

/// Switching profiles: the animated swap, the swipe and ⌘-scroll gesture on the dock, and
/// showing the dock for a moment when it's hidden, so a switch is never invisible.
extension DockController {
    /// How long a hidden dock stays up after a profile switch, in seconds.
    static let profilePeekDuration = 1.5
    static let profileBannerDuration = Duration.milliseconds(1200)

    /// Switches to the profile `offset` places along the list, wrapping around at the ends.
    public func switchProfile(by offset: Int) {
        guard store.profiles.count > 1, offset != 0 else { return }
        switchProfile(to: store.document.profileID(offsetFromActive: offset), direction: offset > 0 ? 1 : -1)
    }

    /// Switches profiles, animated: the old items shrink away as the new ones slide in,
    /// from the right when `direction` is 1 (as for the next profile) or from the left when
    /// it's -1. Without a direction, it follows the profiles' order in the list.
    public func switchProfile(to id: DockProfile.ID, direction: Int? = nil) {
        let profiles = store.profiles
        guard id != store.activeProfileID,
              let newIndex = profiles.firstIndex(where: { $0.id == id }),
              shellState.draggingItemID == nil
        else { return }
        let oldIndex = profiles.firstIndex { $0.id == store.activeProfileID } ?? 0

        shellState.profileSwapDirection = direction ?? (newIndex > oldIndex ? 1 : -1)
        shellState.hoveredItemID = nil
        // The new row may be narrower; let the old one finish leaving before the window fits it.
        holdFrameSize(for: .milliseconds(450))
        withAnimation(.dockProfileSwap) {
            store.selectProfile(id)
        }
        showProfileBanner(profiles[newIndex].name)

        if store.settings.autoHide, !shellState.isVisible {
            reveal()
            scheduleHide(after: Self.profilePeekDuration)
        }
    }

    private func showProfileBanner(_ name: String) {
        shellState.profileBanner = name
        profileBannerTask?.cancel()
        profileBannerTask = Task { [weak self] in
            try? await Task.sleep(for: Self.profileBannerDuration)
            guard let self, !Task.isCancelled else { return }
            shellState.profileBanner = nil
        }
    }

    // MARK: - Scrolling on the dock

    func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            let windowNumber = event.windowNumber
            let scroll = ProfileScrollGesture.Event(event)
            let switched = MainActor.assumeIsolated { self?.handleScroll(scroll, inWindow: windowNumber) ?? false }
            return switched ? nil : event
        }
    }

    func removeScrollMonitor() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
    }

    /// Returns true when the scroll switched profiles.
    private func handleScroll(_ scroll: ProfileScrollGesture.Event, inWindow windowNumber: Int) -> Bool {
        guard let panel, panel.windowNumber == windowNumber,
              store.settings.switchProfilesByScrolling,
              store.profiles.count > 1,
              shellState.isVisible,
              !shellState.isInteracting,
              !shellState.isDragging
        else { return false }
        guard let step = profileScrollGesture.handle(scroll) else { return false }
        switchProfile(by: step)
        return true
    }
}

extension ProfileScrollGesture.Event {
    nonisolated init(_ event: NSEvent) {
        let phase: ProfileScrollGesture.Phase =
            if event.phase.contains(.began) {
                .began
            } else if event.phase.contains(.changed) || event.phase.contains(.stationary) {
                .changed
            } else if event.phase.isEmpty {
                .none
            } else {
                .ended // ended, cancelled, or may begin
            }
        self.init(
            deltaX: Double(event.scrollingDeltaX),
            deltaY: Double(event.scrollingDeltaY),
            phase: phase,
            isMomentum: !event.momentumPhase.isEmpty,
            isCommandDown: event.modifierFlags.contains(.command),
            timestamp: event.timestamp
        )
    }
}

extension Animation {
    /// A profile switch: one row of items gives way to the other.
    static let dockProfileSwap = Animation.easeInOut(duration: 0.3)
}

extension AnyTransition {
    /// How items come and go in a profile switch. The outgoing ones shrink into the dock
    /// wherever they are; the incoming ones slide in from `direction`'s side.
    static func dockProfileSwap(direction: Int, distance: CGFloat, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .offset(x: CGFloat(direction) * distance).combined(with: .opacity),
            removal: .scale(scale: 0.6, anchor: .bottom).combined(with: .opacity)
        )
    }
}
