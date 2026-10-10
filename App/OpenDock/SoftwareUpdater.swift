import AppKit
import Observation
import Sparkle

/// Sparkle 2 updater. Created with the app delegate and started once the app has finished launching.
///
/// OpenDock is a menu-bar app (`LSUIElement`, activation policy `.accessory`), so Sparkle's
/// windows would otherwise have nothing to come forward on. While an update interaction is
/// on screen the policy switches to `.regular`, and it goes back to `.accessory` when the
/// session ends. The Dock icon only shows for that interval.
@MainActor
@Observable
final class SoftwareUpdater {
    /// Sparkle's user-defaults key (`SUEnableAutomaticChecks`). The Info.plist default is on.
    static let automaticChecksDefaultsKey = "SUEnableAutomaticChecks"

    /// Sparkle publishes this over KVO; the menu item enables itself from here.
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private let userInterface = SparkleUserInterface()
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    /// Starts the updater. Call once from `applicationDidFinishLaunching`.
    func start() {
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: userInterface
        )
        self.controller = controller
        canCheckForUpdates = controller.updater.canCheckForUpdates
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) {
            [weak self] _, _ in
            Task { @MainActor in
                self?.canCheckForUpdates = self?.controller?.updater.canCheckForUpdates ?? false
            }
        }
    }

    var automaticallyChecksForUpdates: Bool {
        get {
            if let controller {
                return controller.updater.automaticallyChecksForUpdates
            }
            return UserDefaults.standard.object(forKey: Self.automaticChecksDefaultsKey) as? Bool ?? true
        }
        set {
            if let controller {
                controller.updater.automaticallyChecksForUpdates = newValue
            } else {
                UserDefaults.standard.set(newValue, forKey: Self.automaticChecksDefaultsKey)
            }
        }
    }

    /// User-initiated check. Switches on a regular activation policy first so the progress
    /// window and the result alert can appear, then Sparkle drives the rest.
    func checkForUpdates() {
        guard let controller, controller.updater.canCheckForUpdates else { return }
        SparkleUserInterface.presentUpdateInterface()
        controller.checkForUpdates(nil)
    }
}

/// Shows Sparkle's standard UI on a Dock-less app, then returns to the menu bar.
@MainActor
final class SparkleUserInterface: NSObject, SPUStandardUserDriverDelegate {
    static func presentUpdateInterface() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    static func returnToMenuBar() {
        NSApp.setActivationPolicy(.accessory)
    }

    /// Tells Sparkle this background app handles update presentation, so it doesn't log that
    /// scheduled checks will be missed. Sparkle still shows its standard UI; these hooks make
    /// that UI visible and put the Dock icon away afterwards.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillShowModalAlert() {
        MainActor.assumeIsolated { Self.presentUpdateInterface() }
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _: Bool,
        forUpdate _: SUAppcastItem,
        state _: SPUUserUpdateState
    ) {
        MainActor.assumeIsolated { Self.presentUpdateInterface() }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { Self.returnToMenuBar() }
    }
}
