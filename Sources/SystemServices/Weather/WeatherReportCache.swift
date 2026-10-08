import Foundation
import os

/// Keeps the last report per location so a tile has something to show right after launch
/// and while offline.
@MainActor
public protocol WeatherReportCache: AnyObject {
    func report(forKey key: String) -> WeatherReport?
    func store(_ report: WeatherReport, forKey key: String)
}

/// Holds reports in memory only; for tests.
@MainActor
public final class InMemoryWeatherReportCache: WeatherReportCache {
    public private(set) var reports: [String: WeatherReport] = [:]

    public init(reports: [String: WeatherReport] = [:]) {
        self.reports = reports
    }

    public func report(forKey key: String) -> WeatherReport? { reports[key] }

    public func store(_ report: WeatherReport, forKey key: String) {
        reports[key] = report
    }
}

/// Writes one JSON file per location under `~/Library/Caches/com.newyorkcompute.opendock/Weather`.
/// Losing the directory only costs one extra fetch, which is what Caches is for.
@MainActor
public final class FileWeatherReportCache: WeatherReportCache {
    private let directory: URL
    private let log = Logger(subsystem: "com.newyorkcompute.opendock", category: "WeatherCache")

    public init(directory: URL? = nil) {
        self.directory =
            directory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "com.newyorkcompute.opendock/Weather", directoryHint: .isDirectory)
    }

    private func url(forKey key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "_" }
        return directory.appending(path: "\(String(safe)).json")
    }

    public func report(forKey key: String) -> WeatherReport? {
        guard let data = try? Data(contentsOf: url(forKey: key)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WeatherReport.self, from: data)
    }

    public func store(_ report: WeatherReport, forKey key: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(to: url(forKey: key), options: .atomic)
        } catch {
            log.error(
                "Couldn't cache the weather for \(key, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
