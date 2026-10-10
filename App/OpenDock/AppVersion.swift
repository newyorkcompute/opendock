import Foundation

/// Version strings from the running bundle's Info.plist.
enum AppVersion {
    static var marketing: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static var build: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }

    /// "0.1.0 (42)", or "dev" when the bundle has no short version (a bare `swift run`).
    static var shortAndBuild: String {
        guard let build else { return marketing }
        return "\(marketing) (\(build))"
    }
}
