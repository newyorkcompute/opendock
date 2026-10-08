import Darwin
import Foundation
import Observation

/// Where `SystemActivityMonitor` gets its raw readings. The app uses
/// ``HostSystemActivitySource``; tests substitute scripted values.
public protocol SystemActivitySource: Sendable {
    /// Cumulative ticks for every core, in kernel order. Empty on failure.
    func cpuTicks() -> [CPUTicks]
    func memory() -> MemorySnapshot?
    func disk() -> DiskSnapshot?
    /// 1-, 5- and 15-minute load averages. Empty on failure.
    func loadAverage() -> [Double]
}

/// Reads the live machine through public Mach, sysctl and Foundation APIs:
/// `host_processor_info` for per-core ticks, `host_statistics64` for VM counters,
/// `vm.swapusage` for swap, `getloadavg`, and `URL` volume resource values for disk space.
public struct HostSystemActivitySource: SystemActivitySource {
    /// The volume whose capacity is reported. Defaults to the startup volume.
    public var volumeURL: URL

    public init(volumeURL: URL = URL(fileURLWithPath: "/")) {
        self.volumeURL = volumeURL
    }

    public func cpuTicks() -> [CPUTicks] {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return [] }
        defer {
            let bytes = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), bytes)
        }

        let stride = Int(CPU_STATE_MAX)
        guard Int(infoCount) >= Int(cpuCount) * stride else { return [] }
        return (0 ..< Int(cpuCount)).map { core in
            let base = core * stride
            func tick(_ state: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[base + Int(state)])) }
            return CPUTicks(
                user: tick(CPU_STATE_USER),
                system: tick(CPU_STATE_SYSTEM),
                idle: tick(CPU_STATE_IDLE),
                nice: tick(CPU_STATE_NICE))
        }
    }

    public func memory() -> MemorySnapshot? {
        let host = mach_host_self()
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS, pageSize > 0 else { return nil }

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(host, HOST_VM_INFO64, reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let page = UInt64(pageSize)
        func bytes(_ pages: UInt32) -> UInt64 { UInt64(pages) * page }
        let internalPages = stats.internal_page_count
        let purgeable = stats.purgeable_count
        let app = internalPages > purgeable ? bytes(internalPages - purgeable) : 0

        let swap = Self.swapUsage()
        return MemorySnapshot(
            total: ProcessInfo.processInfo.physicalMemory,
            app: app,
            wired: bytes(stats.wire_count),
            compressed: bytes(stats.compressor_page_count),
            cached: bytes(stats.external_page_count) &+ bytes(purgeable),
            swapUsed: swap?.used ?? 0,
            swapTotal: swap?.total ?? 0)
    }

    private static func swapUsage() -> (used: UInt64, total: UInt64)? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return (used: UInt64(usage.xsu_used), total: UInt64(usage.xsu_total))
    }

    public func disk() -> DiskSnapshot? {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeLocalizedNameKey,
        ]
        guard let values = try? volumeURL.resourceValues(forKeys: keys),
            let total = values.volumeTotalCapacity
        else { return nil }
        // "Important usage" is what Finder reports: it counts purgeable space as free.
        let available =
            values.volumeAvailableCapacityForImportantUsage
            ?? values.volumeAvailableCapacity.map { Int64($0) } ?? 0
        return DiskSnapshot(
            name: values.volumeLocalizedName ?? "Startup Disk",
            total: UInt64(max(0, total)),
            available: UInt64(max(0, available)))
    }

    public func loadAverage() -> [Double] {
        var loads = [Double](repeating: 0, count: 3)
        let count = getloadavg(&loads, 3)
        return count > 0 ? Array(loads.prefix(Int(count))) : []
    }
}

/// Samples CPU, memory and disk on demand and keeps the latest ``snapshot`` and a short
/// CPU ``history`` for sparklines.
///
/// Nothing runs on its own: tiles drive it with ``autoRefresh(every:)`` from a `.task`
/// that is only alive while the dock is visible, so a hidden dock costs no CPU. Use
/// ``shared`` so every tile reads the same data and the machine is sampled once.
@MainActor
@Observable
public final class SystemActivityMonitor {
    /// Process-wide instance shared by all system activity tiles.
    public static let shared = SystemActivityMonitor()

    /// How often tiles ask for a new reading.
    public nonisolated static let defaultInterval: Duration = .seconds(2)
    /// About a minute of history at the default interval.
    public nonisolated static let defaultHistoryLength = 30

    public private(set) var snapshot = SystemActivitySnapshot()
    public private(set) var history: CPUHistory

    @ObservationIgnored private let source: any SystemActivitySource
    @ObservationIgnored private var previousTicks: [CPUTicks] = []
    @ObservationIgnored private var lastRefresh: ContinuousClock.Instant?
    @ObservationIgnored private var pressureSource: (any DispatchSourceMemoryPressure)?
    @ObservationIgnored private var memoryPressure: MemoryPressure = .normal

    public init(
        source: any SystemActivitySource = HostSystemActivitySource(),
        historyLength: Int = SystemActivityMonitor.defaultHistoryLength,
        observesMemoryPressure: Bool = true
    ) {
        self.source = source
        history = CPUHistory(capacity: historyLength)
        // Take the CPU baseline now so the first refresh has something to diff against.
        previousTicks = source.cpuTicks()
        if observesMemoryPressure { startObservingMemoryPressure() }
    }

    isolated deinit {
        pressureSource?.cancel()
    }

    /// Number of cores in the last reading.
    public var coreCount: Int { snapshot.cores.count }

    // MARK: Refresh

    /// Takes a new reading now. CPU usage covers the time since the previous call, so
    /// two calls in quick succession produce a noisy figure; prefer ``autoRefresh(every:)``.
    public func refresh() {
        lastRefresh = ContinuousClock().now
        let ticks = source.cpuTicks()
        let cpu = CPUUsage.aggregate(from: previousTicks, to: ticks)
        // No elapsed ticks means no new information, so the last CPU figures stand.
        let cores = cpu == nil ? snapshot.cores : CPUUsage.perCore(from: previousTicks, to: ticks)
        if !ticks.isEmpty { previousTicks = ticks }

        let newSnapshot = SystemActivitySnapshot(
            date: Date(),
            cpu: cpu ?? snapshot.cpu,
            cores: cores,
            loadAverage: source.loadAverage(),
            memory: source.memory(),
            memoryPressure: memoryPressure,
            disk: source.disk())
        if newSnapshot != snapshot { snapshot = newSnapshot }
        if let cpu { history.append(cpu.total) }
    }

    /// Refreshes only if the last reading is older than three quarters of `interval`, so
    /// several tiles sharing the monitor don't each sample the machine.
    public func refreshIfStale(interval: Duration = SystemActivityMonitor.defaultInterval) {
        if let lastRefresh, ContinuousClock().now - lastRefresh < interval * 0.75 { return }
        refresh()
    }

    /// Samples every `interval` until the surrounding task is cancelled. Run it from a
    /// view's `.task(id:)` keyed on `dockIsVisible` so sampling stops with the dock.
    public func autoRefresh(every interval: Duration = SystemActivityMonitor.defaultInterval) async {
        refreshIfStale(interval: interval)
        if snapshot.cpu == nil {
            // Baseline only: wait a moment so the first figure covers real time.
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            refresh()
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            if Task.isCancelled { return }
            refreshIfStale(interval: interval)
        }
    }

    // MARK: Memory pressure

    private func startObservingMemoryPressure() {
        let dispatchSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical], queue: .main)
        dispatchSource.setEventHandler { [weak self] in
            // Delivered on the main queue, so this runs on the main thread.
            MainActor.assumeIsolated {
                guard let self, let pressureSource = self.pressureSource else { return }
                self.memoryPressureChanged(pressureSource.data)
            }
        }
        pressureSource = dispatchSource
        dispatchSource.activate()
    }

    private func memoryPressureChanged(_ event: DispatchSource.MemoryPressureEvent) {
        let level: MemoryPressure
        if event.contains(.critical) {
            level = .critical
        } else if event.contains(.warning) {
            level = .warning
        } else {
            level = .normal
        }
        guard level != memoryPressure else { return }
        memoryPressure = level
        if snapshot.memoryPressure != level { snapshot.memoryPressure = level }
    }
}
