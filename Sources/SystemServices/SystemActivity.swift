import Foundation

// Models and pure math for the System Activity widget. Nothing here touches the
// kernel; `HostSystemActivitySource` does the reading and `SystemActivityMonitor`
// turns successive readings into a `SystemActivitySnapshot`.

/// Cumulative scheduler ticks for one CPU core, as reported by `host_processor_info`.
/// Usage is the change in these between two readings.
public struct CPUTicks: Sendable, Hashable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    public var total: UInt64 { user &+ system &+ idle &+ nice }
}

/// Share of time a core (or the whole machine) spent busy over an interval, as fractions 0...1.
public struct CPUUsage: Sendable, Hashable {
    /// User-space time, including niced processes.
    public var user: Double
    /// Kernel time.
    public var system: Double

    public init(user: Double, system: Double) {
        self.user = user
        self.system = system
    }

    /// Everything that isn't idle.
    public var total: Double { min(1, user + system) }

    /// The busy fraction between two tick readings, or `nil` when no time has
    /// passed (or the counters went backwards, as they do after a core comes back
    /// from sleep). Caller-facing code treats `nil` as "no reading yet".
    public static func between(_ previous: CPUTicks, and current: CPUTicks) -> CPUUsage? {
        guard current.total > previous.total else { return nil }
        let elapsed = Double(current.total - previous.total)
        func delta(_ keyPath: KeyPath<CPUTicks, UInt64>) -> Double {
            let now = current[keyPath: keyPath]
            let before = previous[keyPath: keyPath]
            return now > before ? Double(now - before) : 0
        }
        let user = (delta(\.user) + delta(\.nice)) / elapsed
        let system = delta(\.system) / elapsed
        return CPUUsage(user: min(1, user), system: min(1, system))
    }

    /// Per-core usages between two readings. Cores whose counters didn't move are
    /// reported as idle; the result is empty when the core count changed.
    public static func perCore(from previous: [CPUTicks], to current: [CPUTicks]) -> [CPUUsage] {
        guard previous.count == current.count else { return [] }
        return zip(previous, current).map { between($0, and: $1) ?? CPUUsage(user: 0, system: 0) }
    }

    /// Whole-machine usage: the sum of every core's ticks, so busy cores and idle cores
    /// average out the same way Activity Monitor's overall figure does.
    public static func aggregate(from previous: [CPUTicks], to current: [CPUTicks]) -> CPUUsage? {
        guard !previous.isEmpty, previous.count == current.count else { return nil }
        func sum(_ ticks: [CPUTicks]) -> CPUTicks {
            ticks.reduce(CPUTicks(user: 0, system: 0, idle: 0, nice: 0)) { partial, next in
                CPUTicks(
                    user: partial.user &+ next.user,
                    system: partial.system &+ next.system,
                    idle: partial.idle &+ next.idle,
                    nice: partial.nice &+ next.nice)
            }
        }
        return between(sum(previous), and: sum(current))
    }
}

/// The kernel's memory pressure level, from a Dispatch memory-pressure source.
public enum MemoryPressure: Sendable, Hashable, Comparable {
    case normal
    case warning
    case critical

    public var label: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }
}

/// Physical memory use, in bytes, split the way Activity Monitor does it.
public struct MemorySnapshot: Sendable, Hashable {
    /// Installed RAM.
    public var total: UInt64
    /// Memory held by apps (internal pages minus purgeable ones).
    public var app: UInt64
    /// Memory the kernel keeps resident.
    public var wired: UInt64
    /// Memory in the compressor.
    public var compressed: UInt64
    /// File cache; reclaimable, so not counted as used.
    public var cached: UInt64
    public var swapUsed: UInt64
    public var swapTotal: UInt64

    public init(
        total: UInt64,
        app: UInt64,
        wired: UInt64,
        compressed: UInt64,
        cached: UInt64,
        swapUsed: UInt64,
        swapTotal: UInt64
    ) {
        self.total = total
        self.app = app
        self.wired = wired
        self.compressed = compressed
        self.cached = cached
        self.swapUsed = swapUsed
        self.swapTotal = swapTotal
    }

    /// Activity Monitor's "Memory Used": apps plus wired plus compressed.
    public var used: UInt64 { min(total, app &+ wired &+ compressed) }

    /// `used` as a share of `total`, 0...1.
    public var usedFraction: Double { SystemActivityMath.fraction(used, of: total) }
}

/// Capacity of one volume, in bytes.
public struct DiskSnapshot: Sendable, Hashable {
    /// The volume's name as Finder shows it, such as "Macintosh HD".
    public var name: String
    public var total: UInt64
    /// Space the system can free up for the user, so purgeable files don't count as used.
    public var available: UInt64

    public init(name: String, total: UInt64, available: UInt64) {
        self.name = name
        self.total = total
        self.available = available
    }

    public var used: UInt64 { total > available ? total - available : 0 }
    public var usedFraction: Double { SystemActivityMath.fraction(used, of: total) }
}

/// One reading of everything the widget shows. Any part can be missing when the
/// kernel call behind it failed or hasn't produced a baseline yet.
public struct SystemActivitySnapshot: Sendable, Hashable {
    public var date: Date
    public var cpu: CPUUsage?
    public var cores: [CPUUsage]
    /// 1-, 5- and 15-minute load averages, or empty when unavailable.
    public var loadAverage: [Double]
    public var memory: MemorySnapshot?
    public var memoryPressure: MemoryPressure
    public var disk: DiskSnapshot?

    public init(
        date: Date = Date(),
        cpu: CPUUsage? = nil,
        cores: [CPUUsage] = [],
        loadAverage: [Double] = [],
        memory: MemorySnapshot? = nil,
        memoryPressure: MemoryPressure = .normal,
        disk: DiskSnapshot? = nil
    ) {
        self.date = date
        self.cpu = cpu
        self.cores = cores
        self.loadAverage = loadAverage
        self.memory = memory
        self.memoryPressure = memoryPressure
        self.disk = disk
    }
}

/// How worried the UI should look about a reading.
public enum ActivityLevel: Sendable, Hashable, Comparable {
    case low
    case elevated
    case high

    /// Spoken beside the percentage, so the green / yellow / red gauge isn't the only cue.
    public var accessibilityDescription: String {
        switch self {
        case .low: "low"
        case .elevated: "elevated"
        case .high: "high"
        }
    }
}

/// Shared arithmetic and thresholds, kept free of UI so they can be tested.
public enum SystemActivityMath {
    /// `part / whole` clamped to 0...1; 0 when `whole` is 0.
    public static func fraction(_ part: UInt64, of whole: UInt64) -> Double {
        guard whole > 0 else { return 0 }
        return min(1, Double(part) / Double(whole))
    }

    /// CPU: green under 60 %, yellow under 85 %, red above.
    public static func cpuLevel(_ fraction: Double) -> ActivityLevel {
        switch fraction {
        case ..<0.6: .low
        case ..<0.85: .elevated
        default: .high
        }
    }

    /// Memory: the kernel's pressure level wins; otherwise fullness past 80 % is elevated.
    public static func memoryLevel(usedFraction: Double, pressure: MemoryPressure) -> ActivityLevel {
        switch pressure {
        case .critical: return .high
        case .warning: return .elevated
        case .normal: return usedFraction < 0.8 ? .low : .elevated
        }
    }

    /// Disk: green under 85 % full, yellow under 95 %, red above.
    public static func diskLevel(_ fraction: Double) -> ActivityLevel {
        switch fraction {
        case ..<0.85: .low
        case ..<0.95: .elevated
        default: .high
        }
    }
}

/// Text formatting shared by the tile and the popover.
public enum SystemActivityFormatting {
    /// "42%" from a 0...1 fraction, clamped and rounded to whole percent.
    public static func percent(_ fraction: Double) -> String {
        guard fraction.isFinite else { return "—%" }
        let clamped = min(1, max(0, fraction))
        return "\(Int((clamped * 100).rounded()))%"
    }

    /// "7.52 GB", "51.2 GB", "512 GB": decimal units like Finder and Activity Monitor, with
    /// fewer decimals as the number grows.
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
        return String(format: "%.\(digits)f %@", value, units[unit])
    }

    /// "2.31 1.98 1.75" for the load averages.
    public static func loadAverage(_ loads: [Double]) -> String {
        loads.map { String(format: "%.2f", $0) }.joined(separator: " ")
    }

    /// "8 cores" / "1 core".
    public static func coreCount(_ count: Int) -> String {
        count == 1 ? "1 core" : "\(count) cores"
    }
}

/// A fixed-length record of recent CPU readings for a sparkline. New samples push
/// the oldest ones out.
public struct CPUHistory: Sendable, Hashable {
    public let capacity: Int
    public private(set) var samples: [Double] = []

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    public mutating func append(_ sample: Double) {
        samples.append(min(1, max(0, sample)))
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    public var isEmpty: Bool { samples.isEmpty }
    public var latest: Double? { samples.last }
}
