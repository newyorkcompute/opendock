import Foundation
import Testing

@testable import SystemServices

@Suite("System activity: CPU math")
struct SystemActivityCPUTests {
    @Test func usageIsTheBusyShareOfElapsedTicks() throws {
        let before = CPUTicks(user: 100, system: 50, idle: 800, nice: 0)
        let after = CPUTicks(user: 130, system: 60, idle: 850, nice: 10)
        let usage = try #require(CPUUsage.between(before, and: after))
        // 100 ticks elapsed: 30 user + 10 nice, 10 system, 50 idle.
        #expect(abs(usage.user - 0.4) < 1e-9)
        #expect(abs(usage.system - 0.1) < 1e-9)
        #expect(abs(usage.total - 0.5) < 1e-9)
    }

    @Test func noElapsedTimeGivesNoReading() {
        let ticks = CPUTicks(user: 1, system: 2, idle: 3, nice: 4)
        #expect(CPUUsage.between(ticks, and: ticks) == nil)
    }

    @Test func countersGoingBackwardsGiveNoReading() {
        let before = CPUTicks(user: 500, system: 500, idle: 500, nice: 0)
        let after = CPUTicks(user: 10, system: 10, idle: 10, nice: 0)
        #expect(CPUUsage.between(before, and: after) == nil)
    }

    @Test func aggregateAveragesAcrossCores() throws {
        let before = [
            CPUTicks(user: 0, system: 0, idle: 0, nice: 0),
            CPUTicks(user: 0, system: 0, idle: 0, nice: 0),
        ]
        let after = [
            CPUTicks(user: 100, system: 0, idle: 0, nice: 0), // fully busy
            CPUTicks(user: 0, system: 0, idle: 100, nice: 0), // fully idle
        ]
        let total = try #require(CPUUsage.aggregate(from: before, to: after))
        #expect(abs(total.total - 0.5) < 1e-9)

        let cores = CPUUsage.perCore(from: before, to: after)
        #expect(cores.count == 2)
        #expect(abs(cores[0].total - 1) < 1e-9)
        #expect(cores[1].total == 0)
    }

    @Test func coreCountChangeIsNotAReading() {
        let one = [CPUTicks(user: 0, system: 0, idle: 0, nice: 0)]
        let two = one + one
        #expect(CPUUsage.aggregate(from: one, to: two) == nil)
        #expect(CPUUsage.perCore(from: one, to: two).isEmpty)
        #expect(CPUUsage.aggregate(from: [], to: []) == nil)
    }

    @Test func idleCoreInAnOtherwiseBusyMachineReadsZero() {
        let before = [CPUTicks(user: 10, system: 0, idle: 10, nice: 0), CPUTicks(user: 5, system: 5, idle: 5, nice: 0)]
        let after = [CPUTicks(user: 10, system: 0, idle: 10, nice: 0), CPUTicks(user: 15, system: 5, idle: 5, nice: 0)]
        let cores = CPUUsage.perCore(from: before, to: after)
        #expect(cores[0] == CPUUsage(user: 0, system: 0))
        #expect(abs(cores[1].user - 1) < 1e-9)
    }
}

@Suite("System activity: memory and disk")
struct SystemActivityMemoryDiskTests {
    @Test func usedMemoryIsAppPlusWiredPlusCompressed() {
        let memory = MemorySnapshot(
            total: 16_000, app: 6_000, wired: 2_000, compressed: 1_000, cached: 4_000, swapUsed: 0, swapTotal: 0)
        #expect(memory.used == 9_000)
        #expect(abs(memory.usedFraction - 0.5625) < 1e-9)
    }

    @Test func usedMemoryNeverExceedsTotal() {
        let memory = MemorySnapshot(
            total: 1_000, app: 900, wired: 900, compressed: 900, cached: 0, swapUsed: 0, swapTotal: 0)
        #expect(memory.used == 1_000)
        #expect(memory.usedFraction == 1)
    }

    @Test func diskUsedIsTotalMinusAvailable() {
        let disk = DiskSnapshot(name: "Macintosh HD", total: 1_000, available: 250)
        #expect(disk.used == 750)
        #expect(abs(disk.usedFraction - 0.75) < 1e-9)

        let odd = DiskSnapshot(name: "Odd", total: 100, available: 400)
        #expect(odd.used == 0)
        #expect(odd.usedFraction == 0)
    }

    @Test func fractionsAreClampedAndSafe() {
        #expect(SystemActivityMath.fraction(5, of: 0) == 0)
        #expect(SystemActivityMath.fraction(10, of: 5) == 1)
        #expect(abs(SystemActivityMath.fraction(1, of: 4) - 0.25) < 1e-9)
    }

    @Test func levelsFollowTheThresholds() {
        #expect(SystemActivityMath.cpuLevel(0.1) == .low)
        #expect(SystemActivityMath.cpuLevel(0.6) == .elevated)
        #expect(SystemActivityMath.cpuLevel(0.85) == .high)

        #expect(SystemActivityMath.diskLevel(0.5) == .low)
        #expect(SystemActivityMath.diskLevel(0.9) == .elevated)
        #expect(SystemActivityMath.diskLevel(0.99) == .high)

        #expect(SystemActivityMath.memoryLevel(usedFraction: 0.5, pressure: .normal) == .low)
        #expect(SystemActivityMath.memoryLevel(usedFraction: 0.9, pressure: .normal) == .elevated)
        #expect(SystemActivityMath.memoryLevel(usedFraction: 0.1, pressure: .warning) == .elevated)
        #expect(SystemActivityMath.memoryLevel(usedFraction: 0.1, pressure: .critical) == .high)
    }
}

@Suite("System activity: formatting")
struct SystemActivityFormattingTests {
    @Test func percentRoundsAndClamps() {
        #expect(SystemActivityFormatting.percent(0.424) == "42%")
        #expect(SystemActivityFormatting.percent(0.425) == "43%")
        #expect(SystemActivityFormatting.percent(0) == "0%")
        #expect(SystemActivityFormatting.percent(1.7) == "100%")
        #expect(SystemActivityFormatting.percent(-0.2) == "0%")
        #expect(SystemActivityFormatting.percent(.nan) == "—%")
    }

    @Test func bytesUseDecimalUnitsWithShrinkingPrecision() {
        #expect(SystemActivityFormatting.bytes(0) == "0 bytes")
        #expect(SystemActivityFormatting.bytes(999) == "999 bytes")
        #expect(SystemActivityFormatting.bytes(1_000) == "1.00 KB")
        #expect(SystemActivityFormatting.bytes(7_520_000_000) == "7.52 GB")
        #expect(SystemActivityFormatting.bytes(51_200_000_000) == "51.2 GB")
        #expect(SystemActivityFormatting.bytes(512_000_000_000) == "512 GB")
        #expect(SystemActivityFormatting.bytes(2_000_000_000_000) == "2.00 TB")
    }

    @Test func loadAverageAndCoreCount() {
        #expect(SystemActivityFormatting.loadAverage([2.314, 1.98, 1.7]) == "2.31 1.98 1.70")
        #expect(SystemActivityFormatting.loadAverage([]) == "")
        #expect(SystemActivityFormatting.coreCount(1) == "1 core")
        #expect(SystemActivityFormatting.coreCount(12) == "12 cores")
    }

    @Test func historyKeepsOnlyTheNewestSamples() {
        var history = CPUHistory(capacity: 3)
        #expect(history.isEmpty)
        for sample in [0.1, 0.2, 0.3, 0.4] { history.append(sample) }
        #expect(history.samples == [0.2, 0.3, 0.4])
        #expect(history.latest == 0.4)
        history.append(5)
        #expect(history.latest == 1)
    }
}

/// Scripted readings so the monitor can be driven without touching the kernel.
private final class ScriptedSource: SystemActivitySource, @unchecked Sendable {
    private let lock = NSLock()
    private var _ticks: [[CPUTicks]]
    private var _memory: MemorySnapshot?
    private var _disk: DiskSnapshot?
    var cpuReads = 0

    init(ticks: [[CPUTicks]], memory: MemorySnapshot? = nil, disk: DiskSnapshot? = nil) {
        _ticks = ticks
        _memory = memory
        _disk = disk
    }

    func cpuTicks() -> [CPUTicks] {
        lock.lock()
        defer { lock.unlock() }
        cpuReads += 1
        guard !_ticks.isEmpty else { return [] }
        return _ticks.count > 1 ? _ticks.removeFirst() : _ticks[0]
    }

    func memory() -> MemorySnapshot? { _memory }
    func disk() -> DiskSnapshot? { _disk }
    func loadAverage() -> [Double] { [1, 2, 3] }
}

@Suite("System activity: monitor")
@MainActor
struct SystemActivityMonitorTests {
    private static func ticks(_ user: UInt64, _ idle: UInt64) -> [CPUTicks] {
        [CPUTicks(user: user, system: 0, idle: idle, nice: 0), CPUTicks(user: user, system: 0, idle: idle, nice: 0)]
    }

    @Test func diffsEachReadingAgainstThePrevious() {
        let source = ScriptedSource(
            ticks: [Self.ticks(0, 0), Self.ticks(50, 50), Self.ticks(100, 50)],
            memory: MemorySnapshot(
                total: 100, app: 10, wired: 10, compressed: 5, cached: 20, swapUsed: 0, swapTotal: 0),
            disk: DiskSnapshot(name: "Disk", total: 100, available: 20))
        let monitor = SystemActivityMonitor(source: source, historyLength: 10, observesMemoryPressure: false)
        #expect(source.cpuReads == 1) // the baseline
        #expect(monitor.snapshot.cpu == nil)

        monitor.refresh()
        #expect(abs((monitor.snapshot.cpu?.total ?? -1) - 0.5) < 1e-9)
        #expect(monitor.coreCount == 2)
        #expect(monitor.snapshot.loadAverage == [1, 2, 3])
        #expect(monitor.snapshot.memory?.used == 25)
        #expect(monitor.snapshot.disk?.used == 80)

        monitor.refresh()
        // 50 more user ticks and no idle ticks: fully busy.
        #expect(abs((monitor.snapshot.cpu?.total ?? -1) - 1) < 1e-9)
        #expect(monitor.history.samples.count == 2)
        #expect(abs(monitor.history.samples[0] - 0.5) < 1e-9)
    }

    @Test func keepsTheLastCPUReadingWhenTheCountersDontMove() {
        let source = ScriptedSource(ticks: [Self.ticks(0, 0), Self.ticks(30, 70)])
        let monitor = SystemActivityMonitor(source: source, historyLength: 10, observesMemoryPressure: false)
        monitor.refresh()
        monitor.refresh() // same ticks again
        #expect(abs((monitor.snapshot.cpu?.total ?? -1) - 0.3) < 1e-9)
        #expect(monitor.coreCount == 2)
        #expect(abs(monitor.snapshot.cores[0].total - 0.3) < 1e-9)
        #expect(monitor.history.samples.count == 1)
        #expect(monitor.snapshot.memory == nil)
        #expect(monitor.snapshot.disk == nil)
    }

    @Test func staleCheckSkipsRecentRefreshes() {
        let source = ScriptedSource(ticks: [Self.ticks(0, 0), Self.ticks(10, 10), Self.ticks(20, 20)])
        let monitor = SystemActivityMonitor(source: source, historyLength: 10, observesMemoryPressure: false)
        monitor.refreshIfStale(interval: .seconds(60))
        monitor.refreshIfStale(interval: .seconds(60))
        #expect(source.cpuReads == 2) // baseline + one refresh
        monitor.refreshIfStale(interval: .zero)
        #expect(source.cpuReads == 3)
    }
}
