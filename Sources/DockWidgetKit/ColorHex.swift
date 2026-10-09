import SwiftUI

public extension Color {
    /// Parses `#RRGGBB`, as the EventKit services report calendar and list colors; falls back
    /// to the system blue on malformed input.
    init(hex: String) {
        var string = hex
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = UInt32(string, radix: 16) else {
            self = .blue
            return
        }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
