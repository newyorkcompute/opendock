import AppKit
import DockCore

extension NSScreen {
    /// The CoreGraphics display ID. Not stable: it can change when a display is
    /// reconnected. Persist `displayUUID` instead.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// The CoreGraphics display UUID, which identifies a display across reconnects,
    /// rearrangement, and restarts.
    public var displayUUID: String? {
        guard let displayID, let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// This screen as `DockPlacement` sees it.
    public var placementScreen: DockPlacement.Screen {
        DockPlacement.Screen(id: displayUUID, name: localizedName, frame: frame, visibleFrame: visibleFrame)
    }
}
