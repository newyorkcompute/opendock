import Foundation
import Testing

@testable import SystemServices

private func reading(
    _ name: String, in bytesIn: UInt64, out bytesOut: UInt64, kind: NetworkInterfaceKind = .ethernet,
    isUp: Bool = true, isRunning: Bool = true, isPointToPoint: Bool = false, addresses: [String] = []
) -> NetworkInterfaceReading {
    NetworkInterfaceReading(
        name: name, kind: kind, isUp: isUp, isRunning: isRunning, isPointToPoint: isPointToPoint,
        bytesIn: bytesIn, bytesOut: bytesOut, addresses: addresses)
}

@Suite("Network: rates from counters")
struct NetworkThroughputTests {
    @Test func rateIsTheCounterDeltaOverTheInterval() throws {
        let before = reading("en0", in: 1_000, out: 500)
        let after = reading("en0", in: 3_000, out: 1_500)
        let rate = try #require(NetworkThroughput.between(before, and: after, elapsed: 2))
        #expect(rate.downloadBytesPerSecond == 1_000)
        #expect(rate.uploadBytesPerSecond == 500)
        #expect(rate.peak == 1_000)
    }

    @Test func tooShortAnIntervalGivesNoReading() {
        let before = reading("en0", in: 0, out: 0)
        let after = reading("en0", in: 10, out: 10)
        #expect(NetworkThroughput.between(before, and: after, elapsed: 0) == nil)
        #expect(NetworkThroughput.between(before, and: after, elapsed: 0.01) == nil)
        #expect(NetworkThroughput.between(before, and: after, elapsed: -1) == nil)
        #expect(NetworkThroughput.between(before, and: after, elapsed: .nan) == nil)
        #expect(NetworkThroughput.between(before, and: after, elapsed: NetworkThroughput.minimumInterval) != nil)
    }

    @Test func thirtyTwoBitCountersWrapAround() throws {
        let nearTheTop = UInt64(UInt32.max) - 999
        let before = reading("en0", in: nearTheTop, out: UInt64(UInt32.max))
        let after = reading("en0", in: 1_000, out: 0)
        let rate = try #require(NetworkThroughput.between(before, and: after, elapsed: 1))
        // 1000 bytes up to the wrap, then 1000 more.
        #expect(rate.downloadBytesPerSecond == 2_000)
        #expect(rate.uploadBytesPerSecond == 1)
    }

    @Test func counterDeltaHandlesEveryDirection() {
        #expect(NetworkThroughput.counterDelta(from: 10, to: 10) == 0)
        #expect(NetworkThroughput.counterDelta(from: 10, to: 25) == 15)
        #expect(NetworkThroughput.counterDelta(from: UInt64(UInt32.max), to: 0) == 1)
        #expect(NetworkThroughput.counterDelta(from: 0xFFFF_FF00, to: 0x10) == 0x110)
        // A reset interface's 64-bit-looking value can't be explained by one wrap.
        #expect(NetworkThroughput.counterDelta(from: 1 << 40, to: 5) == 0)
        #expect(NetworkThroughput.counterDelta(from: 10, to: 5, bits: 0) == 0)
        #expect(NetworkThroughput.counterDelta(from: 10, to: 5, bits: 64) == 0)
        #expect(NetworkThroughput.counterDelta(from: 250, to: 5, bits: 8) == 11)
    }

    @Test func perInterfaceSkipsInterfacesWithoutABaseline() throws {
        let before = [reading("en0", in: 0, out: 0), reading("en1", in: 0, out: 0)]
        let after = [reading("en0", in: 4_000, out: 2_000), reading("utun3", in: 100, out: 100)]
        let rates = NetworkThroughput.perInterface(from: before, to: after, elapsed: 2)
        #expect(rates.count == 1)
        let en0 = try #require(rates["en0"])
        #expect(en0.downloadBytesPerSecond == 2_000)
        #expect(en0.uploadBytesPerSecond == 1_000)
    }

    @Test func throughputsAdd() {
        let total =
            NetworkThroughput(downloadBytesPerSecond: 1, uploadBytesPerSecond: 2)
            + NetworkThroughput(downloadBytesPerSecond: 10, uploadBytesPerSecond: 20)
        #expect(total == NetworkThroughput(downloadBytesPerSecond: 11, uploadBytesPerSecond: 22))
        #expect(NetworkThroughput.zero + total == total)
    }
}

@Suite("Network: which interfaces count")
struct NetworkInterfaceFilterTests {
    @Test func onlyConnectedRealLinksCount() {
        #expect(reading("en0", in: 0, out: 0, kind: .wifi).countsTowardsTotal)
        #expect(reading("en5", in: 0, out: 0, kind: .ethernet).countsTowardsTotal)
        #expect(reading("pdp_ip0", in: 0, out: 0, kind: .cellular).countsTowardsTotal)
        #expect(reading("xyz0", in: 0, out: 0, kind: .other).countsTowardsTotal)
        #expect(!reading("lo0", in: 0, out: 0, kind: .loopback).countsTowardsTotal)
        #expect(!reading("utun3", in: 0, out: 0, kind: .tunnel).countsTowardsTotal)
        #expect(!reading("awdl0", in: 0, out: 0, kind: .virtual).countsTowardsTotal)
        #expect(!reading("en1", in: 0, out: 0, kind: .ethernet, isUp: false).countsTowardsTotal)
        #expect(!reading("en1", in: 0, out: 0, kind: .ethernet, isRunning: false).countsTowardsTotal)
        #expect(!reading("ppp0", in: 0, out: 0, kind: .other, isPointToPoint: true).countsTowardsTotal)
    }

    @Test func kindIsGuessedFromTheName() {
        func kind(_ name: String, loopback: Bool = false, p2p: Bool = false) -> NetworkInterfaceKind {
            NetworkInterfaceReading.kind(forName: name, isLoopback: loopback, isPointToPoint: p2p)
        }
        #expect(kind("lo0", loopback: true) == .loopback)
        #expect(kind("en0") == .ethernet)
        #expect(kind("en12") == .ethernet)
        #expect(kind("utun4") == .tunnel)
        #expect(kind("ppp0") == .tunnel)
        #expect(kind("ipsec0") == .tunnel)
        #expect(kind("gpd0", p2p: true) == .tunnel)
        #expect(kind("awdl0") == .virtual)
        #expect(kind("llw0") == .virtual)
        #expect(kind("bridge0") == .virtual)
        #expect(kind("ap1") == .virtual)
        #expect(kind("anpi0") == .virtual)
        #expect(kind("gif0") == .virtual)
        #expect(kind("stf0") == .virtual)
        #expect(kind("pdp_ip0") == .cellular)
        #expect(kind("something") == .other)
    }

    @Test func selectionReadsAndWritesTheSetting() {
        #expect(NetworkInterfaceSelection(settingValue: "") == .automatic)
        #expect(NetworkInterfaceSelection(settingValue: "  \n") == .automatic)
        #expect(NetworkInterfaceSelection(settingValue: " en0 ") == .named("en0"))
        #expect(NetworkInterfaceSelection.automatic.settingValue == "")
        #expect(NetworkInterfaceSelection.named("en1").settingValue == "en1")

        let tunnel = reading("utun3", in: 0, out: 0, kind: .tunnel)
        #expect(!NetworkInterfaceSelection.automatic.includes(tunnel))
        #expect(NetworkInterfaceSelection.named("utun3").includes(tunnel))
        #expect(!NetworkInterfaceSelection.named("en0").includes(tunnel))
    }

    @Test func snapshotSumsTheSelectedInterfaces() {
        let rate = NetworkThroughput(downloadBytesPerSecond: 100, uploadBytesPerSecond: 10)
        let snapshot = NetworkActivitySnapshot(interfaces: [
            NetworkInterfaceStatus(reading: reading("lo0", in: 0, out: 0, kind: .loopback), throughput: rate),
            NetworkInterfaceStatus(reading: reading("en0", in: 0, out: 0, kind: .wifi), throughput: rate),
            NetworkInterfaceStatus(reading: reading("en5", in: 0, out: 0, kind: .ethernet), throughput: rate),
            NetworkInterfaceStatus(reading: reading("utun3", in: 0, out: 0, kind: .tunnel), throughput: rate),
            NetworkInterfaceStatus(reading: reading("en7", in: 0, out: 0, kind: .ethernet)),
        ])
        #expect(snapshot.interfaces(matching: .automatic).map(\.name) == ["en0", "en5", "en7"])
        #expect(snapshot.throughput(for: .automatic)?.downloadBytesPerSecond == 200)
        #expect(snapshot.throughput(for: .automatic)?.uploadBytesPerSecond == 20)
        #expect(snapshot.throughput(for: .named("utun3")) == rate)
        #expect(snapshot.throughput(for: .named("en7")) == nil)
        #expect(snapshot.throughput(for: .named("en9")) == nil)
        #expect(snapshot.isMissing(.named("en9")))
        #expect(!snapshot.isMissing(.named("en7")))
        #expect(!snapshot.isMissing(.automatic))
        #expect(NetworkActivitySnapshot().throughput(for: .automatic) == nil)
    }

    @Test func listedInterfacesLeaveOutTheSystemsOwn() {
        let snapshot = NetworkActivitySnapshot(interfaces: [
            NetworkInterfaceStatus(reading: reading("lo0", in: 0, out: 0, kind: .loopback, addresses: ["127.0.0.1"])),
            NetworkInterfaceStatus(reading: reading("en0", in: 0, out: 0, kind: .wifi, addresses: ["10.0.0.2"])),
            NetworkInterfaceStatus(reading: reading("en1", in: 0, out: 0, kind: .ethernet, isRunning: false)),
            NetworkInterfaceStatus(reading: reading("en2", in: 0, out: 0, kind: .ethernet, isUp: false)),
            NetworkInterfaceStatus(reading: reading("awdl0", in: 0, out: 0, kind: .virtual, addresses: ["fe80::1"])),
            NetworkInterfaceStatus(reading: reading("utun3", in: 0, out: 0, kind: .tunnel, addresses: ["10.8.0.2"])),
            NetworkInterfaceStatus(
                reading: reading("en3", in: 0, out: 0, kind: .ethernet, isRunning: false, addresses: ["169.254.1.2"])),
        ])
        #expect(snapshot.listedInterfaces().map(\.name) == ["en0", "utun3", "en3"])
        // The chosen interface is always listed so it can be unchosen.
        #expect(snapshot.listedInterfaces(selection: .named("en2")).map(\.name) == ["en0", "en2", "utun3", "en3"])
        #expect(snapshot.listedInterfaces(selection: .named("en9")).map(\.name) == ["en0", "utun3", "en3"])
    }

    @Test func titleCombinesDisplayAndBSDNames() {
        let en0 = reading("en0", in: 0, out: 0)
        #expect(NetworkInterfaceStatus(reading: en0).title == "en0")
        #expect(NetworkInterfaceStatus(reading: en0, displayName: "").title == "en0")
        #expect(NetworkInterfaceStatus(reading: en0, displayName: "en0").title == "en0")
        #expect(NetworkInterfaceStatus(reading: en0, displayName: "Wi-Fi").title == "Wi-Fi (en0)")
    }
}

@Suite("Network: history and chart math")
struct NetworkHistoryTests {
    private let en0 = reading("en0", in: 0, out: 0, kind: .wifi)
    private let utun = reading("utun3", in: 0, out: 0, kind: .tunnel)

    @Test func historyKeepsOnlyTheNewestSamples() {
        var history = NetworkHistory(capacity: 2)
        #expect(history.isEmpty)
        for value in [1.0, 2, 3] {
            history.append(["en0": NetworkThroughput(downloadBytesPerSecond: value, uploadBytesPerSecond: 0)])
        }
        #expect(history.samples.count == 2)
        #expect(history.series(for: .automatic, interfaces: [en0]).download == [2, 3])
        #expect(NetworkHistory(capacity: 0).capacity == 1)
    }

    @Test func seriesFollowTheSelection() {
        var history = NetworkHistory(capacity: 10)
        history.append([
            "en0": NetworkThroughput(downloadBytesPerSecond: 100, uploadBytesPerSecond: 1),
            "utun3": NetworkThroughput(downloadBytesPerSecond: 50, uploadBytesPerSecond: 5),
        ])
        history.append(["utun3": NetworkThroughput(downloadBytesPerSecond: 60, uploadBytesPerSecond: 6)])

        let automatic = history.series(for: .automatic, interfaces: [en0, utun])
        #expect(automatic.download == [100, 0])
        #expect(automatic.upload == [1, 0])

        let tunnel = history.series(for: .named("utun3"), interfaces: [en0, utun])
        #expect(tunnel.download == [50, 60])
        #expect(tunnel.upload == [5, 6])

        let missing = history.series(for: .named("en9"), interfaces: [en0, utun])
        #expect(missing.download == [0, 0])
    }

    @Test func normalizationSharesAScaleWithAFloor() {
        #expect(NetworkMath.normalized([0, 50, 100], peak: 100, floor: 0) == [0, 0.5, 1])
        // Below the floor the chart stays near the bottom instead of filling up.
        #expect(NetworkMath.normalized([0, 50, 100], peak: 100, floor: 200) == [0, 0.25, 0.5])
        #expect(NetworkMath.normalized([5, 500], peak: 5, floor: 0) == [1, 1])
        #expect(NetworkMath.normalized([1, 2], peak: 0, floor: 0) == [0, 0])
        #expect(NetworkMath.normalized([], peak: 10) == [])
        #expect(NetworkMath.normalized([25_000], peak: 25_000) == [0.5])
    }

    @Test func peakSpansSeriesAndIgnoresNaN() {
        #expect(NetworkMath.peak(of: [1, 5], [3, .nan]) == 5)
        #expect(NetworkMath.peak(of: [], []) == 0)
        #expect(NetworkMath.peak(of: [2], [9], [4]) == 9)
    }

    @Test func addressesAreOrderedForReading() {
        let ordered = NetworkMath.orderedAddresses([
            "fe80::1c2b:3d4e%en0", "2001:db8::10", "192.168.1.20", "FE80::2", "10.0.0.5",
        ])
        #expect(ordered == ["192.168.1.20", "10.0.0.5", "2001:db8::10", "fe80::1c2b:3d4e", "FE80::2"])
        #expect(NetworkMath.orderedAddresses([]) == [])
    }
}

@Suite("Network: formatting")
struct NetworkFormattingTests {
    @Test func ratesInBytesUseShortDecimalUnits() {
        #expect(NetworkFormatting.rate(0) == "0 KB/s")
        #expect(NetworkFormatting.rate(40) == "0 KB/s")
        #expect(NetworkFormatting.rate(340) == "0.3 KB/s")
        #expect(NetworkFormatting.rate(9_940) == "9.9 KB/s")
        #expect(NetworkFormatting.rate(9_960) == "10 KB/s")
        #expect(NetworkFormatting.rate(12_400) == "12 KB/s")
        #expect(NetworkFormatting.rate(999_400) == "999 KB/s")
        #expect(NetworkFormatting.rate(999_600) == "1.0 MB/s")
        #expect(NetworkFormatting.rate(1_240_000) == "1.2 MB/s")
        #expect(NetworkFormatting.rate(128_000_000) == "128 MB/s")
        #expect(NetworkFormatting.rate(1_100_000_000) == "1.1 GB/s")
        #expect(NetworkFormatting.rate(5e15) == "5000 TB/s")
        #expect(NetworkFormatting.rate(-1) == "—")
        #expect(NetworkFormatting.rate(.nan) == "—")
        #expect(NetworkFormatting.rate(.infinity) == "—")
    }

    @Test func ratesInBitsMultiplyByEight() {
        #expect(NetworkFormatting.rate(0, unit: .bits) == "0 Kb/s")
        #expect(NetworkFormatting.rate(1_250_000, unit: .bits) == "10 Mb/s")
        #expect(NetworkFormatting.rate(125_000_000, unit: .bits) == "1.0 Gb/s")
        #expect(NetworkFormatting.rate(500, unit: .bits) == "4.0 Kb/s")
    }

    @Test func directedRatesCarryAnArrow() {
        #expect(NetworkFormatting.directedRate(1_240_000, download: true, unit: .bytes) == "↓ 1.2 MB/s")
        #expect(NetworkFormatting.directedRate(500, download: false, unit: .bits) == "↑ 4.0 Kb/s")
    }

    @Test func bytesUseDecimalUnitsWithShrinkingPrecision() {
        #expect(NetworkFormatting.bytes(0) == "0 bytes")
        #expect(NetworkFormatting.bytes(999) == "999 bytes")
        #expect(NetworkFormatting.bytes(1_000) == "1.00 KB")
        #expect(NetworkFormatting.bytes(7_520_000_000) == "7.52 GB")
        #expect(NetworkFormatting.bytes(51_200_000_000) == "51.2 GB")
        #expect(NetworkFormatting.bytes(512_000_000_000) == "512 GB")
    }

    @Test func unitsRoundTripThroughTheirSettingValues() {
        for unit in NetworkRateUnit.allCases {
            #expect(NetworkRateUnit(rawValue: unit.rawValue) == unit)
        }
        #expect(NetworkRateUnit(rawValue: "nibbles") == nil)
    }
}

/// Scripted readings so the monitor can be driven without touching the kernel.
private final class ScriptedSource: NetworkActivitySource, @unchecked Sendable {
    private let lock = NSLock()
    private var _readings: [[NetworkInterfaceReading]]
    private let _descriptions: [String: NetworkInterfaceDescription]
    var interfaceReads = 0
    var descriptionReads = 0

    init(readings: [[NetworkInterfaceReading]], descriptions: [String: NetworkInterfaceDescription] = [:]) {
        _readings = readings
        _descriptions = descriptions
    }

    func interfaces() -> [NetworkInterfaceReading] {
        lock.lock()
        defer { lock.unlock() }
        interfaceReads += 1
        guard !_readings.isEmpty else { return [] }
        return _readings.count > 1 ? _readings.removeFirst() : _readings[0]
    }

    func descriptions() -> [String: NetworkInterfaceDescription] {
        lock.lock()
        defer { lock.unlock() }
        descriptionReads += 1
        return _descriptions
    }
}

@Suite("Network: monitor")
@MainActor
struct NetworkActivityMonitorTests {
    private let start = ContinuousClock().now

    @Test func diffsEachReadingAgainstThePrevious() throws {
        let source = ScriptedSource(
            readings: [
                [reading("en0", in: 0, out: 0), reading("lo0", in: 0, out: 0, kind: .loopback)],
                [reading("en0", in: 2_000, out: 1_000), reading("lo0", in: 500, out: 500, kind: .loopback)],
                [reading("en0", in: 6_000, out: 1_000), reading("lo0", in: 500, out: 500, kind: .loopback)],
            ],
            descriptions: ["en0": NetworkInterfaceDescription(displayName: "Wi-Fi", kind: .wifi)])
        let monitor = NetworkActivityMonitor(source: source, historyLength: 10, now: start)
        #expect(source.interfaceReads == 1) // the baseline
        #expect(!monitor.hasReading)
        #expect(monitor.snapshot.interfaces.isEmpty)

        monitor.refresh(now: start + .seconds(2))
        #expect(monitor.hasReading)
        let total = try #require(monitor.snapshot.throughput(for: .automatic))
        #expect(total.downloadBytesPerSecond == 1_000)
        #expect(total.uploadBytesPerSecond == 500)
        // Loopback has a rate of its own but doesn't count towards the total.
        #expect(monitor.snapshot.throughput(for: .named("lo0"))?.downloadBytesPerSecond == 250)
        let en0 = try #require(monitor.snapshot.interfaces.first { $0.name == "en0" })
        #expect(en0.displayName == "Wi-Fi")
        #expect(en0.reading.kind == .wifi)
        #expect(en0.title == "Wi-Fi (en0)")

        monitor.refresh(now: start + .seconds(4))
        #expect(monitor.snapshot.throughput(for: .automatic)?.downloadBytesPerSecond == 2_000)
        #expect(monitor.snapshot.throughput(for: .automatic)?.uploadBytesPerSecond == 0)
        #expect(monitor.history.samples.count == 2)
        let series = monitor.history.series(for: .automatic, interfaces: monitor.snapshot.interfaces.map(\.reading))
        #expect(series.download == [1_000, 2_000])
        #expect(series.upload == [500, 0])
    }

    @Test func keepsTheLastRateWhenNoTimeHasPassed() {
        let source = ScriptedSource(readings: [
            [reading("en0", in: 0, out: 0)],
            [reading("en0", in: 1_000, out: 0)],
            [reading("en0", in: 1_000_000, out: 0)],
        ])
        let monitor = NetworkActivityMonitor(source: source, historyLength: 10, now: start)
        monitor.refresh(now: start + .seconds(1))
        monitor.refresh(now: start + .seconds(1) + .milliseconds(5))
        #expect(monitor.snapshot.throughput(for: .automatic)?.downloadBytesPerSecond == 1_000)
        #expect(monitor.history.samples.count == 1)
    }

    @Test func anIdleNetworkLeavesTheSnapshotUnchanged() {
        let source = ScriptedSource(readings: [
            [reading("en0", in: 0, out: 0)],
            [reading("en0", in: 1_000, out: 100)],
            [reading("en0", in: 1_000, out: 100)],
            [reading("en0", in: 1_000, out: 100)],
            [reading("en0", in: 1_000, out: 100)],
        ])
        let monitor = NetworkActivityMonitor(source: source, historyLength: 10, now: start)
        monitor.refresh(now: start + .seconds(1))
        #expect(monitor.snapshot.throughput(for: .automatic)?.downloadBytesPerSecond == 1_000)
        monitor.refresh(now: start + .seconds(2))
        #expect(monitor.snapshot.throughput(for: .automatic) == .zero, "the counters stopped moving")

        // Nothing changes from here on, so the snapshot the tiles observe mustn't either.
        let idle = monitor.snapshot
        monitor.refresh(now: start + .seconds(3))
        monitor.refresh(now: start + .seconds(4))
        #expect(monitor.snapshot == idle)
        #expect(monitor.history.samples.count == 4, "the sparkline still gets its samples")
    }

    @Test func describesInterfacesOnlyWhenTheSetChanges() {
        let source = ScriptedSource(readings: [
            [reading("en0", in: 0, out: 0)],
            [reading("en0", in: 1, out: 0)],
            [reading("en0", in: 2, out: 0)],
            [reading("en0", in: 3, out: 0), reading("en5", in: 0, out: 0)],
            [reading("en0", in: 4, out: 0), reading("en5", in: 1, out: 0)],
        ])
        let monitor = NetworkActivityMonitor(source: source, historyLength: 10, now: start)
        #expect(source.descriptionReads == 0)
        monitor.refresh(now: start + .seconds(1))
        monitor.refresh(now: start + .seconds(2))
        #expect(source.descriptionReads == 1)
        monitor.refresh(now: start + .seconds(3))
        #expect(source.descriptionReads == 2)
        monitor.refresh(now: start + .seconds(4))
        #expect(source.descriptionReads == 2)
        #expect(monitor.snapshot.interfaces.map(\.name) == ["en0", "en5"])
    }

    @Test func staleCheckSkipsRecentRefreshes() {
        let source = ScriptedSource(readings: [[reading("en0", in: 0, out: 0)]])
        let monitor = NetworkActivityMonitor(source: source, historyLength: 10, now: start)
        monitor.refreshIfStale(interval: .seconds(60), now: start + .seconds(1))
        monitor.refreshIfStale(interval: .seconds(60), now: start + .seconds(2))
        #expect(source.interfaceReads == 2) // baseline + one refresh
        monitor.refreshIfStale(interval: .seconds(60), now: start + .seconds(50))
        #expect(source.interfaceReads == 3)
        monitor.refreshIfStale(interval: .zero, now: start + .seconds(50))
        #expect(source.interfaceReads == 4)
    }

    @Test func emptyReadingsLeaveTheBaselineAlone() throws {
        let source = ScriptedSource(readings: [
            [reading("en0", in: 0, out: 0)],
            [],
            [reading("en0", in: 3_000, out: 0)],
        ])
        let monitor = NetworkActivityMonitor(source: source, historyLength: 10, now: start)
        monitor.refresh(now: start + .seconds(1))
        #expect(monitor.snapshot.interfaces.isEmpty)
        monitor.refresh(now: start + .seconds(3))
        // Measured against the baseline, not the failed read.
        let total = try #require(monitor.snapshot.throughput(for: .automatic))
        #expect(total.downloadBytesPerSecond == 1_000)
    }

    @Test func durationsConvertToSeconds() {
        #expect(NetworkActivityMonitor.seconds(.seconds(2)) == 2)
        #expect(abs(NetworkActivityMonitor.seconds(.milliseconds(1_500)) - 1.5) < 1e-9)
        #expect(NetworkActivityMonitor.seconds(.zero) == 0)
    }
}
