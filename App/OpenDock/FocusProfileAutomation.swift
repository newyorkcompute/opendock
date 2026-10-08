import DockCore
import SystemServices
import os

/// Switches profiles as Focus modes come and go, following the rules in Settings > Profiles.
/// Switches go through `ProfileSwitcher`, so they animate like any other.
final class FocusProfileAutomation {
    private let store: DockStore
    private let monitor: FocusModeMonitor
    private let switcher: ProfileSwitcher
    private var lastAppliedMode: String?
    private var hasApplied = false
    private let log = Logger(subsystem: "com.newyorkcompute.opendock", category: "FocusProfileAutomation")

    init(store: DockStore, monitor: FocusModeMonitor, switcher: ProfileSwitcher) {
        self.store = store
        self.monitor = monitor
        self.switcher = switcher
    }

    /// Applies the Focus that's on now (or the end of one that was on when OpenDock last
    /// ran), then every change after that.
    func start() {
        observe()
    }

    private func observe() {
        let (access, mode) = withObservationTracking {
            (monitor.access, monitor.activeModeID)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
        guard access == .granted, !hasApplied || mode != lastAppliedMode else { return }
        hasApplied = true
        lastAppliedMode = mode
        guard let target = store.profileForFocusChange(to: mode) else { return }
        log.info("Focus \(mode ?? "off", privacy: .public): switching to profile \(target, privacy: .public)")
        switcher.select(target)
    }
}
