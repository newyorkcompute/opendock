import DockCore
import Foundation

/// The apps pinned in Apple's Dock, read from its `com.apple.dock` `persistent-apps`
/// preference. Read-only: OpenDock never changes Apple's Dock layout.
public enum AppleDockApps {
    static let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")

    /// Finder first, since Apple's Dock always shows it, then the pinned apps that are still
    /// installed, without duplicates. Just Finder when the preference can't be read.
    public static func read(fileManager: FileManager = .default) -> [URL] {
        let domain = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(domain)
        let tiles = CFPreferencesCopyAppValue("persistent-apps" as CFString, domain) as? [[String: Any]] ?? []
        var seen = Set<String>()
        return ([finder] + appURLs(fromPersistentApps: tiles)).filter {
            fileManager.fileExists(atPath: $0.path) && seen.insert($0.normalizedPath).inserted
        }
    }

    /// The app bundle URLs in `persistent-apps` tiles, in Dock order. Spacers and anything
    /// that isn't a local `.app` are skipped.
    static func appURLs(fromPersistentApps tiles: [[String: Any]]) -> [URL] {
        tiles.compactMap { tile in
            if let type = tile["tile-type"] as? String, type != "file-tile" { return nil }
            guard let data = tile["tile-data"] as? [String: Any],
                let file = data["file-data"] as? [String: Any],
                let string = file["_CFURLString"] as? String
            else { return nil }
            // `_CFURLStringType` 0 is a POSIX path; 15, what the Dock writes, is a URL string.
            let isPath = (file["_CFURLStringType"] as? Int) == 0
            let url = isPath ? URL(fileURLWithPath: string) : URL(string: string)
            guard let url, url.isFileURL, url.pathExtension == "app" else { return nil }
            return url.standardizedFileURL
        }
    }
}
