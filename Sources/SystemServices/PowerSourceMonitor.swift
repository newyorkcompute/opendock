import Foundation
import IOKit.ps
import Observation

/// A single entry from IOKit's power-source list: the internal battery, a UPS,
/// or a battery-backed accessory such as AirPods or a Magic Mouse.
public struct PowerSource: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case internalBattery
        case ups
        case accessory
        case other
    }

    public let id: Int
    public var name: String
    public var kind: Kind
    /// Charge level in whole percent (0...100), if the source reports capacity.
    public var percentage: Int?
    public var isCharging: Bool
    public var isCharged: Bool
    /// True when this source reports that it is running from external power.
    public var isOnExternalPower: Bool
    /// Minutes until empty while discharging; `nil` when unknown or calculating.
    public var minutesToEmpty: Int?
    /// Minutes until full while charging; `nil` when unknown or calculating.
    public var minutesToFull: Int?
    /// Battery health string (for example "Good"), if reported.
    public var health: String?
    /// Battery condition string (for example "Service Recommended"), if reported.
    public var condition: String?
}

/// Reads IOKit power-source information and keeps it current.
///
/// Updates are driven by an `IOPSNotificationCreateRunLoopSource` on the main run
/// loop, with a slow timer as a safety net. Observers only re-render when the
/// snapshot actually changes. Use ``shared`` so every tile reads the same data.
@MainActor
@Observable
public final class PowerSourceMonitor {
    /// A battery-reporting accessory (AirPods, Magic Mouse, ...).
    public struct Accessory: Sendable, Hashable, Identifiable {
        public let id: Int
        public let name: String
        public let percentage: Int
        public let isCharging: Bool
    }

    /// Process-wide instance shared by all battery tiles.
    public static let shared = PowerSourceMonitor()

    /// Every power source currently reported by the system.
    public private(set) var sources: [PowerSource] = []
    /// True when the Mac is running from external power (also true on desktops).
    public private(set) var isPluggedIn = true

    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var fallbackTimer: Timer?

    public init() {
        refresh()
        startObserving()
    }

    isolated deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        fallbackTimer?.invalidate()
    }

    // MARK: Derived state

    private var internalBattery: PowerSource? {
        sources.first { $0.kind == .internalBattery }
    }

    /// True on Macs with an internal battery; false on desktops.
    public var hasBattery: Bool { internalBattery != nil }
    /// Internal battery charge in percent.
    public var percentage: Int? { internalBattery?.percentage }
    public var isCharging: Bool { internalBattery?.isCharging ?? false }
    public var isFullyCharged: Bool { internalBattery?.isCharged ?? false }

    /// Minutes until empty (on battery) or until full (charging); `nil` if unknown.
    public var timeRemainingMinutes: Int? {
        guard let battery = internalBattery else { return nil }
        return battery.isCharging ? battery.minutesToFull : battery.minutesToEmpty
    }

    /// "Good", "Normal", ... if the system reports it.
    public var batteryHealth: String? { internalBattery?.condition ?? internalBattery?.health }

    /// Battery-reporting Bluetooth accessories, in system order.
    public var accessories: [Accessory] {
        sources.compactMap { source in
            guard source.kind == .accessory, let percentage = source.percentage else { return nil }
            return Accessory(id: source.id, name: source.name, percentage: percentage, isCharging: source.isCharging)
        }
    }

    // MARK: Refresh

    /// Re-reads the power sources. Cheap; safe to call at any time.
    public func refresh() {
        let (newSources, newPluggedIn) = Self.readSources()
        if newSources != sources { sources = newSources }
        if newPluggedIn != isPluggedIn { isPluggedIn = newPluggedIn }
    }

    private func startObserving() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let unmanaged = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue()
            // The source is attached to the main run loop, so this runs on the main thread.
            MainActor.assumeIsolated { monitor.refresh() }
        }, context) {
            let source = unmanaged.takeRetainedValue()
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }

        // Safety net: time-remaining estimates and some accessories don't always notify.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        fallbackTimer = timer
    }

    // MARK: IOKit

    private nonisolated static func readSources() -> ([PowerSource], Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return ([], true) }

        var result: [PowerSource] = []
        for (index, ps) in list.enumerated() {
            guard let description = IOPSGetPowerSourceDescription(info, ps)?
                .takeUnretainedValue() as? [String: Any]
            else { continue }
            if let present = description[kIOPSIsPresentKey] as? Bool, !present { continue }
            result.append(makeSource(index: index, description: description))
        }

        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let pluggedIn = providing.map { $0 == kIOPSACPowerValue } ?? true
        return (result, pluggedIn)
    }

    private nonisolated static func makeSource(index: Int, description d: [String: Any]) -> PowerSource {
        let typeString = d[kIOPSTypeKey] as? String
        let transport = d[kIOPSTransportTypeKey] as? String
        let kind: PowerSource.Kind = switch typeString {
        case kIOPSInternalBatteryType: .internalBattery
        case kIOPSUPSType: .ups
        case "Accessory Source": .accessory
        default: transport == "Bluetooth" ? .accessory : .other
        }

        var percentage: Int?
        if let current = d[kIOPSCurrentCapacityKey] as? Int {
            let maximum = (d[kIOPSMaxCapacityKey] as? Int) ?? 100
            percentage = maximum > 0 ? min(100, max(0, Int((Double(current) / Double(maximum) * 100).rounded()))) : current
        }

        func minutes(_ key: String) -> Int? {
            guard let value = d[key] as? Int, value >= 0 else { return nil }
            return value
        }

        return PowerSource(
            id: index,
            name: (d[kIOPSNameKey] as? String) ?? "Battery",
            kind: kind,
            percentage: percentage,
            isCharging: (d[kIOPSIsChargingKey] as? Bool) ?? false,
            isCharged: (d[kIOPSIsChargedKey] as? Bool) ?? false,
            isOnExternalPower: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue,
            minutesToEmpty: minutes(kIOPSTimeToEmptyKey),
            minutesToFull: minutes(kIOPSTimeToFullChargeKey),
            health: d[kIOPSBatteryHealthKey] as? String,
            condition: (d[kIOPSBatteryHealthConditionKey] as? String)
        )
    }
}
