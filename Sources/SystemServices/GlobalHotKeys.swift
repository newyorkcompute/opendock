import Carbon.HIToolbox
import DockCore
import Observation
import os

/// System-wide keyboard shortcuts, through Carbon's `RegisterEventHotKey`. Unlike a global
/// `NSEvent` monitor it needs no Accessibility permission, and the key press goes only to
/// OpenDock, not also to the app in front.
///
/// ```swift
/// let hotKeys = GlobalHotKeys { name in print("pressed", name) }
/// hotKeys.update(["next": HotKey(keyCode: 124, modifiers: [.control, .option, .command])])
/// ```
@MainActor
@Observable
public final class GlobalHotKeys {
    /// Shortcuts the system refused, usually because another app already uses them.
    public private(set) var unavailable: Set<HotKey> = []

    /// While true nothing is registered, so a shortcut recorder sees the keys it's given.
    public var isPaused: Bool {
        get { paused }
        set {
            guard newValue != paused else { return }
            paused = newValue
            apply()
        }
    }

    @ObservationIgnored private var paused = false
    @ObservationIgnored private let onPress: @MainActor (String) -> Void
    @ObservationIgnored private var wanted: [String: HotKey] = [:]
    @ObservationIgnored private var registered: [UInt32: (name: String, ref: EventHotKeyRef)] = [:]
    @ObservationIgnored private var handler: EventHandlerRef?
    @ObservationIgnored private var nextID: UInt32 = 1
    @ObservationIgnored private let log = Logger(subsystem: "com.newyorkcompute.opendock", category: "GlobalHotKeys")

    public init(onPress: @escaping @MainActor (String) -> Void) {
        self.onPress = onPress
    }

    isolated deinit {
        unregisterAll()
        if let handler { RemoveEventHandler(handler) }
    }

    /// Replaces every shortcut. Keys name the actions passed back to `onPress`.
    public func update(_ shortcuts: [String: HotKey]) {
        guard shortcuts != wanted else { return }
        wanted = shortcuts
        apply()
    }

    private func apply() {
        unregisterAll()
        var refused: Set<HotKey> = []
        if !paused {
            installHandlerIfNeeded()
            for (name, hotKey) in wanted.sorted(by: { $0.key < $1.key }) {
                if !register(hotKey, name: name) { refused.insert(hotKey) }
            }
        }
        if refused != unavailable { unavailable = refused }
    }

    private func register(_ hotKey: HotKey, name: String) -> Bool {
        let id = nextID
        nextID &+= 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(hotKey.keyCode),
            Self.carbonModifiers(hotKey.modifiers),
            EventHotKeyID(signature: hotKeySignature, id: id),
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            log.error("Couldn't register the \(name, privacy: .public) shortcut: \(status)")
            return false
        }
        registered[id] = (name, ref)
        return true
    }

    private func unregisterAll() {
        for (_, entry) in registered { UnregisterEventHotKey(entry.ref) }
        registered = [:]
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventHandler,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        if status != noErr { log.error("Couldn't install the shortcut handler: \(status)") }
    }

    fileprivate func pressed(_ id: UInt32) {
        guard let name = registered[id]?.name else { return }
        onPress(name)
    }

    private static func carbonModifiers(_ modifiers: HotKey.Modifiers) -> UInt32 {
        var flags = 0
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        return UInt32(flags)
    }
}

/// "ODK!": marks the hot keys OpenDock registered.
private let hotKeySignature: OSType = 0x4F44_4B21

/// Carbon delivers hot key events on the main thread, through the main run loop.
private func hotKeyEventHandler(_: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?)
    -> OSStatus
{
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == hotKeySignature else { return OSStatus(eventNotHandledErr) }
    let id = hotKeyID.id
    let address = Int(bitPattern: userData)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<GlobalHotKeys>.fromOpaque(pointer).takeUnretainedValue().pressed(id)
    }
    return noErr
}
