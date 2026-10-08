import Foundation
import Testing

@testable import SystemServices

@MainActor
@Suite("System sounds")
struct SystemSoundsTests {
    @Test func interfaceSoundsAreOnUnlessTurnedOff() {
        #expect(SystemSounds.interfaceSoundsEnabled(from: nil))
        #expect(SystemSounds.interfaceSoundsEnabled(from: NSNumber(value: 1)))
        #expect(SystemSounds.interfaceSoundsEnabled(from: NSNumber(value: true)))
        #expect(!SystemSounds.interfaceSoundsEnabled(from: NSNumber(value: 0)))
        #expect(!SystemSounds.interfaceSoundsEnabled(from: NSNumber(value: false)))
        #expect(SystemSounds.interfaceSoundsEnabled(from: "garbage"), "an unreadable value doesn't silence the dock")
    }

    @Test func poofSoundIsOptional() {
        // Whatever this Mac has, looking for it must not fail; `playPoof` is silent without it.
        _ = SystemSounds.poofSound()
        #expect(!SystemSounds.poofCandidates.isEmpty)
        #expect(SystemSounds.poofCandidates.allSatisfy { $0.hasPrefix("/System/") })
    }
}
