import DockWidgetKit
import SwiftUI
import Testing

@MainActor
@Suite("Color from hex")
struct ColorHexTests {
    @Test func parsesSixDigitHexWithOrWithoutHash() {
        #expect(Color(hex: "#FF8000") == Color(.sRGB, red: 1, green: 128 / 255, blue: 0))
        #expect(Color(hex: "ff8000") == Color(.sRGB, red: 1, green: 128 / 255, blue: 0))
        #expect(Color(hex: "#000000") == Color(.sRGB, red: 0, green: 0, blue: 0))
    }

    @Test func fallsBackToBlueOnMalformedInput() {
        #expect(Color(hex: "") == .blue)
        #expect(Color(hex: "#FFF") == .blue)
        #expect(Color(hex: "#GGGGGG") == .blue)
        #expect(Color(hex: "#FF8000FF") == .blue)
    }
}
