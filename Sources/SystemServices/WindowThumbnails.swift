import CoreGraphics
@preconcurrency import ScreenCaptureKit
import os

/// Captures still images of windows. `MinimizedWindowMonitor` calls this only after
/// Screen Recording is already granted; an implementation must not ask for it.
@MainActor
public protocol WindowThumbnailCapturing: AnyObject {
    /// One image per window id that could be captured. Missing ids are simply absent.
    func capture(windowIDs: [Int]) async -> [Int: CGImage]
}

/// Thumbnails through ScreenCaptureKit.
///
/// `SCShareableContent` prompts for Screen Recording if it isn't granted, so this refuses
/// to call it unless `CGPreflightScreenCaptureAccess()` already says yes. A window that
/// can't be captured (a minimized window the capture API doesn't list, for instance) is
/// left out, and the dock draws the app icon instead.
@MainActor
public final class SystemWindowThumbnailCapturer: WindowThumbnailCapturing {
    private let log = Logger(subsystem: "com.newyorkcompute.opendock", category: "WindowThumbnails")

    public init() {}

    public func capture(windowIDs: [Int]) async -> [Int: CGImage] {
        guard CGPreflightScreenCaptureAccess(), !windowIDs.isEmpty else { return [:] }
        let content: SCShareableContent
        do {
            // Off-screen windows included: a minimized window isn't on screen.
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            log.debug("Couldn't list windows for thumbnails: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
        var byID: [Int: SCWindow] = [:]
        for window in content.windows {
            let id = Int(window.windowID)
            if byID[id] == nil { byID[id] = window }
        }
        var images: [Int: CGImage] = [:]
        for id in windowIDs {
            guard let window = byID[id] else { continue }
            do {
                images[id] = try await Self.image(of: window)
            } catch {
                log.debug(
                    "Couldn't capture window \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return images
    }

    /// A still of `window`, long side capped so a huge window doesn't become a huge image.
    private static func image(of window: SCWindow) async throws -> CGImage {
        let scale: CGFloat = 2
        let width = max(window.frame.width, 1) * scale
        let height = max(window.frame.height, 1) * scale
        let cap: CGFloat = 800
        let longest = max(width, height)
        let factor = longest > cap ? cap / longest : 1
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((width * factor).rounded()))
        configuration.height = max(1, Int((height * factor).rounded()))
        configuration.scalesToFit = true
        configuration.showsCursor = false
        let filter = SCContentFilter(desktopIndependentWindow: window)
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
