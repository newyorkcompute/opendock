import AppKit
import os

/// Sending things over AirDrop, and the AirDrop window in Finder.
@MainActor
public enum AirDropService {
    /// Finder's AirDrop window is an app of its own inside Finder; opening it shows the
    /// window, as Go > AirDrop does. Apple's Dock lets this app be pinned for the same reason.
    public static let finderWindowURL = URL(
        fileURLWithPath: "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app")

    /// The AirDrop icon, as Finder shows it, or nil on a system without the AirDrop app.
    public static let icon: NSImage? = {
        guard FileManager.default.fileExists(atPath: finderWindowURL.path) else { return nil }
        return NSWorkspace.shared.icon(forFile: finderWindowURL.path)
    }()

    /// Whether this Mac can send `items` over AirDrop right now. False when there's nothing
    /// to send, or Wi-Fi and Bluetooth are both off.
    public static func canSend(_ items: [URL]) -> Bool {
        guard !items.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return false }
        return service.canPerform(withItems: items)
    }

    /// Shows the AirDrop sheet, listing the devices nearby, for `items`. Returns false when
    /// it couldn't (see `canSend`).
    @discardableResult
    public static func send(_ items: [URL]) -> Bool {
        guard !items.isEmpty, let service = NSSharingService(named: .sendViaAirDrop),
            service.canPerform(withItems: items)
        else {
            log.info("AirDrop can't send \(items.count) item(s) right now")
            return false
        }
        // The sheet is a window of ours, so bring the app forward for it; the dock itself
        // never activates (see `DockPanel`).
        NSApp.activate()
        service.perform(withItems: items)
        return true
    }

    /// Opens the AirDrop window in Finder.
    public static func openFinderWindow(workspace: any AppWorkspace = SystemAppWorkspace()) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: finderWindowURL, configuration: configuration)
    }

    private static let log = Logger(subsystem: "com.newyorkcompute.opendock", category: "AirDrop")
}
