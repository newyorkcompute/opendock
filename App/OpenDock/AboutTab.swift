import AppKit
import DockCore
import SwiftUI
import SystemServices

/// App identity, version, links, and a shortcut to the data file.
struct AboutTab: View {
    private static let repositoryURL = URL(string: "https://github.com/newyorkcompute/opendock")!
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: 4) {
                Text("OpenDock")
                    .font(.title.weight(.semibold))
                Text(versionString)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            VStack(spacing: 4) {
                Text("An open-source custom Dock for macOS with widgets.")
                Text("Open source, MIT License.")
                    .foregroundStyle(.secondary)
                Text("Inspired by [Dockset](https://dockset.app).")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            Link("github.com/newyorkcompute/opendock", destination: Self.repositoryURL)

            Button("Reveal Data File") { revealDataFile() }
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info["CFBundleVersion"] as? String
        return build.map { "Version \(version) (\($0))" } ?? "Version \(version)"
    }

    /// Selects `dock.json` in Finder, or its folder if it hasn't been written yet.
    private func revealDataFile() {
        let fileURL = DockStorage.default().fileURL
        let target = FileManager.default.fileExists(atPath: fileURL.path)
            ? fileURL
            : fileURL.deletingLastPathComponent()
        AppLauncher.revealInFinder(target)
    }
}
