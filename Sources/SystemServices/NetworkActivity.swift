import Foundation

// Models and pure math for the Network widget. Nothing here touches the kernel:
// `HostNetworkActivitySource` reads the interfaces and `NetworkActivityMonitor` turns
// successive readings into a `NetworkActivitySnapshot`. Everything in this file is
// Foundation-only so the arithmetic can be tested anywhere.

/// What kind of link an interface is, as far as the widget cares.
public enum NetworkInterfaceKind: Sendable, Hashable {
    case wifi
    case ethernet
    case cellular
    case loopback
    /// A VPN or other tunnel (`utun`, `ppp`, `ipsec`).
    case tunnel
    /// Something the system uses internally: AirDrop's `awdl`, bridges, `gif`/`stf`.
    case virtual
    case other

    public var systemImage: String {
        switch self {
        case .wifi: "wifi"
        case .ethernet: "cable.connector"
        case .cellular: "antenna.radiowaves.left.and.right"
        case .loopback: "arrow.triangle.2.circlepath"
        case .tunnel: "lock.shield"
        case .virtual: "point.3.connected.trianglepath.dotted"
        case .other: "network"
        }
    }
}

/// One reading of one interface: cumulative byte counters plus what the interface is.
/// The counters come from `getifaddrs`'s `if_data`, which is 32 bits wide on macOS, so
/// they wrap every 4 GiB; `NetworkThroughput.between` accounts for that.
public struct NetworkInterfaceReading: Sendable, Hashable, Identifiable {
    /// BSD name such as `en0`.
    public var name: String
    public var kind: NetworkInterfaceKind
    /// `IFF_UP`.
    public var isUp: Bool
    /// `IFF_RUNNING`: the link is actually established.
    public var isRunning: Bool
    /// `IFF_POINTOPOINT`: a tunnel or dial-up link.
    public var isPointToPoint: Bool
    /// Cumulative bytes received, as the kernel reported them.
    public var bytesIn: UInt64
    /// Cumulative bytes sent.
    public var bytesOut: UInt64
    /// Numeric IPv4 and IPv6 addresses assigned to the interface, IPv4 first.
    public var addresses: [String]

    public var id: String { name }

    public init(
        name: String,
        kind: NetworkInterfaceKind = .other,
        isUp: Bool = true,
        isRunning: Bool = true,
        isPointToPoint: Bool = false,
        bytesIn: UInt64,
        bytesOut: UInt64,
        addresses: [String] = []
    ) {
        self.name = name
        self.kind = kind
        self.isUp = isUp
        self.isRunning = isRunning
        self.isPointToPoint = isPointToPoint
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.addresses = addresses
    }

    /// Whether this interface's traffic counts towards the automatic total: a real link
    /// that is up and connected. Loopback never does. Tunnels don't either, because what
    /// goes through a VPN also goes through the physical link underneath it, and
    /// AirDrop's `awdl`/`llw`, bridges and the like only carry traffic the system makes.
    public var countsTowardsTotal: Bool {
        guard isUp, isRunning, !isPointToPoint else { return false }
        switch kind {
        case .wifi, .ethernet, .cellular, .other: return true
        case .loopback, .tunnel, .virtual: return false
        }
    }

    /// Classifies an interface from its BSD name and flags. The host source refines
    /// this with SystemConfiguration when it can; this is the fallback for
    /// interfaces the system doesn't describe.
    public static func kind(forName name: String, isLoopback: Bool, isPointToPoint: Bool) -> NetworkInterfaceKind {
        if isLoopback || name.hasPrefix("lo") { return .loopback }
        if isPointToPoint || name.hasPrefix("utun") || name.hasPrefix("ppp") || name.hasPrefix("ipsec") {
            return .tunnel
        }
        let virtualPrefixes = ["awdl", "llw", "bridge", "gif", "stf", "ap", "anpi", "XHC", "vmnet", "feth"]
        if virtualPrefixes.contains(where: { name.hasPrefix($0) }) { return .virtual }
        if name.hasPrefix("pdp_ip") { return .cellular }
        if name.hasPrefix("en") { return .ethernet }
        return .other
    }
}

/// What the system says about an interface, from SystemConfiguration: the name shown in
/// Network Settings and a kind more reliable than the BSD name suggests (on Apple
/// silicon Wi-Fi is `en0`).
public struct NetworkInterfaceDescription: Sendable, Hashable {
    public var displayName: String
    public var kind: NetworkInterfaceKind?

    public init(displayName: String, kind: NetworkInterfaceKind?) {
        self.displayName = displayName
        self.kind = kind
    }
}

/// Bytes per second in each direction over an interval.
public struct NetworkThroughput: Sendable, Hashable {
    public var downloadBytesPerSecond: Double
    public var uploadBytesPerSecond: Double

    public init(downloadBytesPerSecond: Double, uploadBytesPerSecond: Double) {
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
    }

    public static let zero = NetworkThroughput(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)

    /// The larger of the two directions, for scaling a chart.
    public var peak: Double { max(downloadBytesPerSecond, uploadBytesPerSecond) }

    public static func + (lhs: NetworkThroughput, rhs: NetworkThroughput) -> NetworkThroughput {
        NetworkThroughput(
            downloadBytesPerSecond: lhs.downloadBytesPerSecond + rhs.downloadBytesPerSecond,
            uploadBytesPerSecond: lhs.uploadBytesPerSecond + rhs.uploadBytesPerSecond)
    }

    /// `if_data`'s counters are `u_int32_t` on macOS.
    public static let counterBits = 32

    /// How far a cumulative counter moved, allowing for it wrapping around once. A
    /// counter that went backwards by more than a wrap can explain (the interface was
    /// reset, or `counterBits` is wrong) reads as no change rather than a huge burst.
    public static func counterDelta(from previous: UInt64, to current: UInt64, bits: Int = counterBits) -> UInt64 {
        if current >= previous { return current - previous }
        guard bits > 0, bits < 64 else { return 0 }
        let modulus = UInt64(1) << UInt64(bits)
        guard previous < modulus, current < modulus else { return 0 }
        return modulus - previous + current
    }

    /// Readings closer together than this don't make a rate: a handful of bytes over a
    /// few milliseconds would read as a huge burst.
    public static let minimumInterval: TimeInterval = 0.2

    /// The rate between two readings of the same interface at least ``minimumInterval``
    /// seconds apart, or `nil` when too little time has passed. Callers treat `nil` as
    /// "no reading yet".
    public static func between(
        _ previous: NetworkInterfaceReading,
        and current: NetworkInterfaceReading,
        elapsed: TimeInterval
    ) -> NetworkThroughput? {
        guard elapsed.isFinite, elapsed >= minimumInterval else { return nil }
        let received = counterDelta(from: previous.bytesIn, to: current.bytesIn)
        let sent = counterDelta(from: previous.bytesOut, to: current.bytesOut)
        return NetworkThroughput(
            downloadBytesPerSecond: Double(received) / elapsed,
            uploadBytesPerSecond: Double(sent) / elapsed)
    }

    /// Rates for every interface present in both readings, by name. Interfaces that
    /// appeared since the previous reading have no baseline and are left out.
    public static func perInterface(
        from previous: [NetworkInterfaceReading],
        to current: [NetworkInterfaceReading],
        elapsed: TimeInterval
    ) -> [String: NetworkThroughput] {
        let before = Dictionary(previous.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var rates: [String: NetworkThroughput] = [:]
        for reading in current {
            guard let earlier = before[reading.name],
                let rate = between(earlier, and: reading, elapsed: elapsed)
            else { continue }
            rates[reading.name] = rate
        }
        return rates
    }
}

/// Which interfaces a tile adds up.
public enum NetworkInterfaceSelection: Sendable, Hashable {
    /// Every interface whose `countsTowardsTotal` is true.
    case automatic
    /// One interface by BSD name, whatever it is.
    case named(String)

    /// `.automatic` for an empty or blank name, as the `interface` setting stores it.
    public init(settingValue: String) {
        let trimmed = settingValue.trimmingCharacters(in: .whitespacesAndNewlines)
        self = trimmed.isEmpty ? .automatic : .named(trimmed)
    }

    public var settingValue: String {
        switch self {
        case .automatic: ""
        case let .named(name): name
        }
    }

    public func includes(_ reading: NetworkInterfaceReading) -> Bool {
        switch self {
        case .automatic: reading.countsTowardsTotal
        case let .named(name): reading.name == name
        }
    }
}

/// One interface as the widget shows it: the latest reading plus its current rate.
public struct NetworkInterfaceStatus: Sendable, Hashable, Identifiable {
    public var reading: NetworkInterfaceReading
    /// A friendlier name from the system, such as "Wi-Fi" or "Thunderbolt Bridge".
    public var displayName: String?
    /// Missing until two readings exist.
    public var throughput: NetworkThroughput?

    public var id: String { reading.name }
    public var name: String { reading.name }

    public init(reading: NetworkInterfaceReading, displayName: String? = nil, throughput: NetworkThroughput? = nil) {
        self.reading = reading
        self.displayName = displayName
        self.throughput = throughput
    }

    /// "Wi-Fi (en0)" when the system named it, otherwise just "en0".
    public var title: String {
        guard let displayName, !displayName.isEmpty, displayName != reading.name else { return reading.name }
        return "\(displayName) (\(reading.name))"
    }
}

/// Everything the widget knows at one moment.
public struct NetworkActivitySnapshot: Sendable, Hashable {
    public var date: Date
    /// Every interface the kernel listed, in kernel order.
    public var interfaces: [NetworkInterfaceStatus]

    public init(date: Date = Date(), interfaces: [NetworkInterfaceStatus] = []) {
        self.date = date
        self.interfaces = interfaces
    }

    /// The interfaces `selection` adds up, whether or not they have a rate yet.
    public func interfaces(matching selection: NetworkInterfaceSelection) -> [NetworkInterfaceStatus] {
        interfaces.filter { selection.includes($0.reading) }
    }

    /// Combined rate of the selected interfaces, or `nil` when none of them has a
    /// reading yet (or none exists).
    public func throughput(for selection: NetworkInterfaceSelection) -> NetworkThroughput? {
        let rates = interfaces(matching: selection).compactMap(\.throughput)
        guard !rates.isEmpty else { return nil }
        return rates.reduce(.zero, +)
    }

    /// Whether `selection` names an interface the machine doesn't have right now.
    public func isMissing(_ selection: NetworkInterfaceSelection) -> Bool {
        guard case .named = selection else { return false }
        return interfaces(matching: selection).isEmpty
    }

    /// The interfaces worth a row in the popover or the settings: anything that's
    /// connected or has an address, except loopback and the system's own interfaces
    /// (AirDrop's `awdl0` is always "running"). Whatever `selection` names is always
    /// listed, so a chosen interface can be seen and unchosen.
    public func listedInterfaces(selection: NetworkInterfaceSelection = .automatic) -> [NetworkInterfaceStatus] {
        interfaces.filter { status in
            if case let .named(name) = selection, status.name == name { return true }
            let reading = status.reading
            switch reading.kind {
            case .loopback, .virtual: return false
            case .wifi, .ethernet, .cellular, .tunnel, .other:
                return reading.isUp && (reading.isRunning || !reading.addresses.isEmpty)
            }
        }
    }
}

/// A fixed-length record of recent per-interface rates for a sparkline. Each sample is
/// the rates by interface name at one instant, so any selection can be charted later.
public struct NetworkHistory: Sendable, Hashable {
    public let capacity: Int
    public private(set) var samples: [[String: NetworkThroughput]] = []

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    public mutating func append(_ sample: [String: NetworkThroughput]) {
        samples.append(sample)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    public var isEmpty: Bool { samples.isEmpty }

    /// Download and upload rates over time for `selection`, oldest first. An interface
    /// missing from a sample contributes nothing to it.
    public func series(for selection: NetworkInterfaceSelection, interfaces: [NetworkInterfaceReading]) -> (
        download: [Double], upload: [Double]
    ) {
        let names = Set(interfaces.filter { selection.includes($0) }.map(\.name))
        var download: [Double] = []
        var upload: [Double] = []
        download.reserveCapacity(samples.count)
        upload.reserveCapacity(samples.count)
        for sample in samples {
            var total = NetworkThroughput.zero
            for (name, rate) in sample where names.contains(name) {
                total = total + rate
            }
            download.append(total.downloadBytesPerSecond)
            upload.append(total.uploadBytesPerSecond)
        }
        return (download, upload)
    }
}

/// Shared arithmetic, kept free of UI so it can be tested.
public enum NetworkMath {
    /// A chart scaled to its own peak never shows the difference between idle and
    /// busy, so the scale never drops below this (bytes per second).
    public static let minimumChartScale: Double = 50_000

    /// Scales `series` to 0...1 against the larger of its peak and `floor`, so both
    /// directions of a chart share one scale and a quiet minute stays near the bottom.
    public static func normalized(_ series: [Double], peak: Double, floor: Double = minimumChartScale) -> [Double] {
        let scale = max(peak, floor)
        guard scale > 0 else { return series.map { _ in 0 } }
        return series.map { min(1, max(0, $0 / scale)) }
    }

    /// The largest value across several series, ignoring anything that isn't finite.
    public static func peak(of series: [Double]...) -> Double {
        series.joined().filter(\.isFinite).max() ?? 0
    }

    /// Addresses in the order people look for them: IPv4, then routable IPv6, then IPv6
    /// link-local (`fe80::…`), each group in its original order. Zone suffixes such as
    /// `%en0` are dropped.
    public static func orderedAddresses(_ addresses: [String]) -> [String] {
        let stripped = addresses.map { address -> String in
            guard let percent = address.firstIndex(of: "%") else { return address }
            return String(address[..<percent])
        }
        let v4 = stripped.filter { !$0.contains(":") }
        let v6 = stripped.filter { $0.contains(":") }
        let linkLocal = v6.filter { $0.lowercased().hasPrefix("fe80:") }
        let routable = v6.filter { !$0.lowercased().hasPrefix("fe80:") }
        return v4 + routable + linkLocal
    }
}

/// Whether speeds read in bytes (KB/s, as Finder and Activity Monitor count) or bits
/// (Mb/s, as internet plans are sold).
public enum NetworkRateUnit: String, Sendable, Hashable, CaseIterable {
    case bytes
    case bits
}

/// Text formatting shared by the tile and the popover.
public enum NetworkFormatting {
    /// "0 KB/s", "0.3 KB/s", "12 KB/s", "1.2 MB/s", "128 MB/s", "1.1 GB/s" from bytes per
    /// second: one decimal under 10, none above, so the text stays short. Units are
    /// decimal (1000) like Finder's and never smaller than kilo, so a quiet link reads
    /// "0 KB/s" rather than a few bytes bouncing around. In bits the labels are "Kb/s",
    /// "Mb/s", "Gb/s".
    public static func rate(_ bytesPerSecond: Double, unit: NetworkRateUnit = .bytes) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return "—" }
        let suffixes =
            switch unit {
            case .bytes: ["KB/s", "MB/s", "GB/s", "TB/s"]
            case .bits: ["Kb/s", "Mb/s", "Gb/s", "Tb/s"]
            }
        var value = (unit == .bits ? bytesPerSecond * 8 : bytesPerSecond) / 1000
        var index = 0
        while value >= 999.5, index < suffixes.count - 1 {
            value /= 1000
            index += 1
        }
        let text = value < 0.05 ? "0" : formatted(value, digits: value < 9.95 ? 1 : 0)
        return text + " " + suffixes[index]
    }

    /// `rate` with its direction's arrow in front: "↓ 1.2 MB/s".
    public static func directedRate(_ bytesPerSecond: Double, download: Bool, unit: NetworkRateUnit) -> String {
        (download ? "↓ " : "↑ ") + rate(bytesPerSecond, unit: unit)
    }

    /// "12.3 MB" / "1.02 GB": decimal units, for the popover's totals.
    public static func bytes(_ count: UInt64) -> String {
        let units = ["bytes", "KB", "MB", "GB", "TB", "PB"]
        var value = Double(count)
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        if unit == 0 { return "\(count) \(units[0])" }
        let digits = value < 10 ? 2 : value < 100 ? 1 : 0
        return formatted(value, digits: digits) + " " + units[unit]
    }

    /// Fixed-point text with a period, whatever the machine's region, like
    /// `SystemActivityFormatting`.
    static func formatted(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }
}
