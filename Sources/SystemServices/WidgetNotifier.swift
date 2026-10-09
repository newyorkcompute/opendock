import AppKit
import UserNotifications

/// Posts notifications (banners in Notification Center) on behalf of widgets, such as a
/// focus session ending or an alarm going off, and plays the alert sounds that go with them.
///
/// `UNUserNotificationCenter` only works inside an app bundle with a bundle identifier; it
/// crashes in a bare executable (`swift run`, tests, Xcode's package scheme). Everything here
/// checks `isAvailable` first and otherwise does nothing, so widgets never need to.
@MainActor
public final class WidgetNotifier: NSObject {
    public static let shared = WidgetNotifier()

    /// Whether this process can post notifications at all (see the type's documentation).
    nonisolated public static let isAvailable = canNotify(
        bundleURL: Bundle.main.bundleURL, bundleIdentifier: Bundle.main.bundleIdentifier)

    /// The alert sound played when a timer ends, from the system's own set.
    static let alertSoundName = "Glass"

    private var center: UNUserNotificationCenter? {
        Self.isAvailable ? UNUserNotificationCenter.current() : nil
    }

    /// Set once the first notification is posted, so the first ask comes from something the
    /// user did (starting a timer, turning an alarm on), not from the dock appearing.
    private var hasRequestedAuthorization = false

    /// The looping alarm sound while an alarm rings, and the last one-off chime. `NSSound`
    /// stops when released, so they're held until `stopRinging` or the next chime.
    private var ringing: NSSound?
    private var chiming: NSSound?

    override private init() {
        super.init()
        center?.delegate = self
    }

    /// A process can post notifications when it runs from an `.app` bundle with an identifier.
    nonisolated static func canNotify(bundleURL: URL, bundleIdentifier: String?) -> Bool {
        bundleIdentifier != nil && bundleURL.pathExtension == "app"
    }

    /// Ask for permission to show banners and play sounds, if that hasn't happened yet.
    /// macOS asks the user once; later calls are free.
    public func requestAuthorizationIfNeeded() {
        guard let center, !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Show a banner now. `identifier` lets a later `withdraw` or a repeat replace it.
    public func post(title: String, body: String, identifier: String, sound: Bool) {
        guard let center else { return }
        requestAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        center.add(request) { _ in }
    }

    /// Take a notification back, for example an alarm's banner once it's been stopped.
    public func withdraw(identifier: String) {
        center?.removeDeliveredNotifications(withIdentifiers: [identifier])
        center?.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    // MARK: Sounds

    /// Play the alert sound once, for a timer that ended.
    public func chime() {
        guard let sound = NSSound(named: Self.alertSoundName) else { return }
        chiming?.stop()
        chiming = sound
        sound.play()
    }

    /// Play the alert sound over and over until `stopRinging`, for an alarm.
    public func startRinging() {
        guard let sound = NSSound(named: Self.alertSoundName) else { return }
        ringing?.stop()
        sound.loops = true
        sound.play()
        ringing = sound
    }

    public func stopRinging() {
        ringing?.stop()
        ringing = nil
    }
}

extension WidgetNotifier: UNUserNotificationCenterDelegate {
    /// Show banners even while OpenDock is the active app (its Settings window is open),
    /// which the system otherwise suppresses.
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
