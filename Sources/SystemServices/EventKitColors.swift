import AppKit
import EventKit

enum EventKitColors {
    /// The `#RRGGBB` (sRGB) form of a calendar's color, or the system blue when it has none.
    static func hex(for color: CGColor?) -> String {
        guard let color, let srgb = NSColor(cgColor: color)?.usingColorSpace(.sRGB) else { return "#0A84FF" }
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(
            format: "#%02X%02X%02X", byte(srgb.redComponent), byte(srgb.greenComponent), byte(srgb.blueComponent))
    }
}
