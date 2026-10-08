import Foundation

/// Notices new items landing in a folder kept in the dock, so its icon can hop once, the
/// way Apple's Dock bounces Downloads when a download finishes.
///
/// It only sees how many entries the folder has: the count comes from the folder's own
/// metadata, which can be read without the access that listing the folder would ask the
/// user for (Downloads, Desktop, and Documents are protected). An item arriving means the
/// count went up; items being renamed or removed don't count. Pure bookkeeping, so it can
/// be unit tested.
public struct FolderArrivals: Hashable, Sendable {
    /// Arrivals closer together than this hop as one: a download that lands as a partial
    /// file and is then replaced, or a batch of files being unpacked, bounces the icon
    /// once rather than once per file.
    public static let quietPeriod: TimeInterval = 1.5

    private var count: Int?
    private var lastArrival: Date?

    public init() {}

    /// Records the folder's entry count as of `date`. Returns true when items have arrived
    /// since the last count and the icon should bounce. The first count only sets the
    /// baseline: whatever the folder holds when it's first seen isn't new.
    public mutating func update(count: Int, at date: Date) -> Bool {
        defer { self.count = count }
        guard let previous = self.count, count > previous else { return false }
        if let lastArrival, date.timeIntervalSince(lastArrival) < Self.quietPeriod { return false }
        lastArrival = date
        return true
    }
}
