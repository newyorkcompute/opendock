import AppKit

/// The system's own interface sounds, played the way Apple's Dock plays them: only if the
/// system has them, and only while the user has interface sounds turned on.
@MainActor
public enum SystemSounds {
    /// Where macOS keeps the Dock's "poof" sound (an item dragged off the Dock), in the
    /// order to try. The location isn't API and has moved before; without it, no sound.
    static let poofCandidates = [
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/poof item off dock.aif",
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/poof.aif",
        "/System/Library/CoreServices/Dock.app/Contents/Resources/poof.aif",
    ]

    /// The sound playing now. `NSSound` stops when it's released, so it's held until the
    /// next one replaces it.
    private static var playing: NSSound?

    /// Play the poof, if the system has it and interface sounds are on. Silent otherwise.
    public static func playPoof() {
        guard interfaceSoundsEnabled, let sound = poofSound() else { return }
        playing = sound
        sound.play()
    }

    /// The first poof sound file the system has.
    static func poofSound() -> NSSound? {
        for path in poofCandidates where FileManager.default.fileExists(atPath: path) {
            if let sound = NSSound(contentsOfFile: path, byReference: true) { return sound }
        }
        return nil
    }

    /// The user's "Play user interface sound effects" setting (Sound settings), which the
    /// Dock's sounds follow. On unless turned off.
    static var interfaceSoundsEnabled: Bool {
        interfaceSoundsEnabled(from: UserDefaults.standard.object(forKey: "com.apple.sound.uiaudio.enabled"))
    }

    /// Reads the setting's stored value, which is a number (0 or 1) when it has been set.
    nonisolated static func interfaceSoundsEnabled(from value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return true }
        return number.boolValue
    }
}
