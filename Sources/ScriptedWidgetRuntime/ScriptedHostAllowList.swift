import Foundation

/// Which hosts a scripted widget's `opendock.fetch` may contact. A pattern is an exact host
/// (`api.github.com`) or one leading wildcard label (`*.open-meteo.com`). Matching is
/// case-insensitive. The wildcard matches one or more labels in front of the suffix, and not
/// the suffix itself: `*.open-meteo.com` matches `api.open-meteo.com` and
/// `a.b.open-meteo.com`, and not `open-meteo.com`.
public enum ScriptedHostAllowList {
    /// Whether `pattern` is one the manifest may declare. A wildcard's suffix has to be a host
    /// with at least two labels, so `*.com` isn't a way to ask for the whole web.
    public static func isValidPattern(_ pattern: String) -> Bool {
        if pattern.hasPrefix("*.") {
            let suffix = String(pattern.dropFirst(2))
            return suffix.contains(".") && isValidHost(suffix)
        }
        return isValidHost(pattern)
    }

    /// A DNS host: labels of ASCII letters, digits and hyphens, not empty, not starting or
    /// ending with a hyphen. No trailing dot, no empty labels.
    public static func isValidHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253, !host.hasPrefix("."), !host.hasSuffix("."), !host.contains("..")
        else { return false }
        let labels = host.split(separator: ".")
        guard !labels.isEmpty else { return false }
        return labels.allSatisfy { label in
            guard (1 ... 63).contains(label.count), let first = label.first, let last = label.last else { return false }
            guard first != "-", last != "-" else { return false }
            return label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }

    /// Whether `host` matches `pattern`. `host` is compared as given, so pass the URL's host
    /// (no port, no user).
    public static func matches(host: String, pattern: String) -> Bool {
        let host = host.lowercased()
        let pattern = pattern.lowercased()
        if pattern.hasPrefix("*.") {
            let suffix = String(pattern.dropFirst(1))
            return host.hasSuffix(suffix) && host.count > suffix.count
        }
        return host == pattern
    }

    /// Whether `host` matches any declared pattern.
    public static func allows(host: String, patterns: [String]) -> Bool {
        patterns.contains { matches(host: host, pattern: $0) }
    }

    /// Why `url` may not be fetched, or nil when it may. Checked before any connection, and
    /// again for every redirect.
    public static func denial(of url: URL, patterns: [String]) -> ScriptedFetchDenial? {
        guard url.scheme?.lowercased() == "https" else { return .notHTTPS }
        if url.user != nil || url.password != nil { return .credentials }
        guard let host = url.host?.trimmingCharacters(in: CharacterSet(charactersIn: "[]")), !host.isEmpty else {
            return .missingHost
        }
        guard allows(host: host, patterns: patterns) else { return .hostNotAllowed(host) }
        return nil
    }
}

/// Why a fetch URL was refused before a connection was made.
public enum ScriptedFetchDenial: Equatable, Sendable {
    case notHTTPS
    case credentials
    case missingHost
    case hostNotAllowed(String)

    /// The host a permission error is about, when there is one.
    public var host: String? {
        if case let .hostNotAllowed(host) = self { return host }
        return nil
    }

    public var message: String {
        switch self {
        case .notHTTPS:
            return "Fetch URLs have to be https."
        case .credentials:
            return "Fetch URLs can't include a username or password."
        case .missingHost:
            return "The fetch URL has no host."
        case let .hostNotAllowed(host):
            return "Can't contact \(host). Add it to permissions.network in manifest.json to allow it."
        }
    }
}
