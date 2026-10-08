import AppKit
import DockCore
import SwiftUI
import SystemServices

/// A button that records a global shortcut. Click it, then press the keys; Esc cancels and
/// Delete clears. The app's own global shortcuts are paused while it listens.
struct HotKeyRecorder: View {
    @Binding var hotKey: HotKey?

    @Environment(GlobalHotKeys.self) private var hotKeys
    @State private var recorder = HotKeyRecording()

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 4) {
                Button(action: toggleRecording) {
                    Text(title)
                        .monospacedDigit()
                        .frame(minWidth: 110)
                }
                if hotKey != nil, !recorder.isRecording {
                    Button {
                        hotKey = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear Shortcut")
                }
            }
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear { recorder.stop() }
    }

    private var title: String {
        if recorder.isRecording { return "Type Shortcut…" }
        return hotKey.map(HotKeyFormatter.string(for:)) ?? "Record Shortcut"
    }

    private var note: String? {
        if recorder.isRecording { return recorder.hint ?? "Esc to cancel, Delete to clear" }
        if let hotKey, hotKeys.unavailable.contains(hotKey) { return "Another app is using this shortcut." }
        return nil
    }

    private func toggleRecording() {
        guard !recorder.isRecording else {
            recorder.stop()
            return
        }
        recorder.start(pausing: hotKeys) { result in
            switch result {
            case let .set(newValue): hotKey = newValue
            case .clear: hotKey = nil
            case .cancel: break
            }
        }
    }
}

/// Listens to the keyboard for `HotKeyRecorder`, swallowing key presses until it has a
/// usable shortcut.
@Observable
final class HotKeyRecording {
    enum Result {
        case set(HotKey)
        case clear
        case cancel
    }

    private(set) var isRecording = false
    /// Why the last key press wasn't accepted.
    private(set) var hint: String?

    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var finish: ((Result) -> Void)?
    @ObservationIgnored private weak var pausedHotKeys: GlobalHotKeys?

    isolated deinit {
        stop()
    }

    func start(pausing hotKeys: GlobalHotKeys, finish: @escaping (Result) -> Void) {
        stop()
        self.finish = finish
        pausedHotKeys = hotKeys
        hotKeys.isPaused = true
        hint = nil
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
            MainActor.assumeIsolated {
                self?.keyPressed(keyCode, flags: NSEvent.ModifierFlags(rawValue: flags))
            }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        pausedHotKeys?.isPaused = false
        pausedHotKeys = nil
        finish = nil
        if isRecording { isRecording = false }
    }

    private func keyPressed(_ keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        let modifiers = HotKey.Modifiers(flags)
        if modifiers.isEmpty {
            switch keyCode {
            case 53: return complete(.cancel) // Esc
            case 51, 117: return complete(.clear) // Delete, Forward Delete
            default: break
            }
        }
        let hotKey = HotKey(keyCode: keyCode, modifiers: modifiers)
        guard hotKey.isValidGlobalShortcut else {
            hint = "Include ⌘ or ⌃ in the shortcut"
            return
        }
        complete(.set(hotKey))
    }

    private func complete(_ result: Result) {
        let finish = finish
        stop()
        finish?(result)
    }
}

extension HotKey.Modifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.shift) { insert(.shift) }
    }
}
