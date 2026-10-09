import Foundation
import os

/// Keeps the last series per symbol and range so a tile has something to show right after
/// launch and while offline.
@MainActor
public protocol StockCache: AnyObject {
    func series(forKey key: String) -> StockSeries?
    func store(_ series: StockSeries, forKey key: String)
}

/// Holds series in memory only; for tests.
@MainActor
public final class InMemoryStockCache: StockCache {
    public private(set) var entries: [String: StockSeries] = [:]

    public init(entries: [String: StockSeries] = [:]) {
        self.entries = entries
    }

    public func series(forKey key: String) -> StockSeries? { entries[key] }

    public func store(_ series: StockSeries, forKey key: String) {
        entries[key] = series
    }
}

/// Writes one JSON file per key under `~/Library/Caches/com.newyorkcompute.opendock/Stocks`.
/// Losing the directory only costs one extra fetch, which is what Caches is for.
@MainActor
public final class FileStockCache: StockCache {
    private let directory: URL
    private let log = Logger(subsystem: "com.newyorkcompute.opendock", category: "StockCache")

    public init(directory: URL? = nil) {
        self.directory =
            directory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "com.newyorkcompute.opendock/Stocks", directoryHint: .isDirectory)
    }

    private func url(forKey key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "_" }
        return directory.appending(path: "\(String(safe)).json")
    }

    public func series(forKey key: String) -> StockSeries? {
        guard let data = try? Data(contentsOf: url(forKey: key)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(StockSeries.self, from: data)
    }

    public func store(_ series: StockSeries, forKey key: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(series).write(to: url(forKey: key), options: .atomic)
        } catch {
            log.error("Couldn't cache \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
