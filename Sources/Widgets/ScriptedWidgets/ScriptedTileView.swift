import DockCore
import DockWidgetKit
import ScriptedWidgetRuntime
import SwiftUI

/// The in-dock tile of a scripted widget: whatever its script's last `render()` described, or
/// a placeholder saying why there's nothing to draw yet (no widget chosen, not installed,
/// loading, or an error).
struct ScriptedTileView: View {
    let instance: WidgetInstance

    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.dockWidgetScale) private var scale
    @Environment(\.dockEdge) private var edge
    @Environment(\.dockIsVisible) private var isVisible
    @State private var library = ScriptedWidgetLibrary.shared
    @State private var model = ScriptedWidgetModel()

    /// Everything that should restart the render loop when it changes.
    private struct RunKey: Equatable {
        var packageID: String?
        var revision: ScriptedWidgetPackage.Revision?
        var settings: [String: String]
        var compact: Bool
        var visible: Bool
    }

    var body: some View {
        let packageID = ScriptedWidgetSettings(instance: instance).packageID
        let package = packageID.flatMap(library.package(for:))
        let key = RunKey(
            packageID: packageID, revision: package?.revision, settings: instance.settings, compact: edge.isVertical,
            visible: isVisible)
        // The tile's `minWidth` is in icon widths at rest; WidgetTile scales it by the magnification.
        WidgetTile(minWidth: model.tile?.minWidth.map { $0 * iconSize / scale }) {
            content(packageID: packageID, package: package)
        }
        .task(id: key) {
            library.loadIfNeeded()
            await model.run(
                package: package, settings: instance.settings, compact: edge.isVertical, visible: isVisible,
                library: library)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(package: package))
    }

    @ViewBuilder
    private func content(packageID: String?, package: ScriptedWidgetPackage?) -> some View {
        if packageID == nil {
            placeholder(
                symbol: ScriptedWidget.systemImage, title: ScriptedWidget.displayName, caption: "Choose one in Settings"
            )
        } else if let package {
            if let error = model.error {
                placeholder(
                    symbol: "exclamationmark.triangle", title: package.manifest.name, caption: error.shortDescription)
            } else if let tile = model.tile {
                ScriptedElementsView(elements: tile.elements)
            } else {
                placeholder(symbol: package.manifest.symbol, title: package.manifest.name, caption: "Loading…")
            }
        } else {
            placeholder(symbol: "questionmark.square.dashed", title: "Not installed", caption: packageID ?? "")
        }
    }

    private func placeholder(symbol: String, title: String, caption: String) -> some View {
        WidgetStack(spacing: iconSize * (edge.isVertical ? 0.06 : 0.14)) {
            Image(systemName: symbol)
                .font(.system(size: iconSize * 0.4, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: iconSize * 0.5, height: iconSize * 0.5)
            VStack(alignment: edge.isVertical ? .center : .leading, spacing: 0) {
                WidgetPrimaryText(title)
                WidgetSecondaryText(caption)
            }
            .frame(maxWidth: edge.isVertical ? nil : CGFloat(iconSize * 2.6), alignment: .leading)
        }
    }

    private func accessibilityLabel(package: ScriptedWidgetPackage?) -> String {
        guard let package else { return "Scripted widget: none chosen" }
        if let error = model.error { return "\(package.manifest.name): \(error.shortDescription)" }
        guard let tile = model.tile else { return "\(package.manifest.name): loading" }
        return tile.accessibilityLabel ?? tile.defaultAccessibilityLabel
    }
}

/// A tile's top-level elements, side by side along the bottom edge and stacked on a side edge.
struct ScriptedElementsView: View {
    let elements: [ScriptedElement]

    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.dockEdge) private var edge

    var body: some View {
        WidgetStack(spacing: iconSize * (edge.isVertical ? 0.06 : 0.14)) {
            ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                ScriptedElementView(element: element)
            }
        }
    }
}

/// One element, drawn with the shared widget views so it matches the built-in tiles.
struct ScriptedElementView: View {
    let element: ScriptedElement

    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.dockEdge) private var edge

    var body: some View {
        switch element {
        case let .text(text):
            textView(text)
        case let .number(number):
            numberView(number)
        case let .progress(progress):
            progressView(progress)
        case let .icon(icon):
            Image(systemName: icon.symbol)
                .font(.system(size: iconSize * Self.symbolScale(icon.size), weight: .medium))
                .foregroundStyle(icon.color?.color ?? .primary)
                .frame(width: iconSize * Self.symbolScale(icon.size) * 1.25)
                .accessibilityHidden(true)
        case let .sparkline(sparkline):
            WidgetSparklineSeries(
                samples: sparkline.samples, capacity: sparkline.capacity ?? sparkline.samples.count,
                color: sparkline.color?.color ?? .blue
            )
            .frame(width: iconSize * 1.2, height: iconSize * 0.5)
        case let .row(group):
            HStack(spacing: spacing(group, default: 0.14)) { children(group) }
        case let .column(group):
            VStack(alignment: group.alignment.horizontal, spacing: spacing(group, default: 0)) { children(group) }
        case .spacer:
            Spacer(minLength: 0)
        case .unsupported:
            EmptyView()
        }
    }

    @ViewBuilder
    private func textView(_ text: ScriptedText) -> some View {
        switch text.style {
        case .primary:
            WidgetPrimaryText(text.text).foregroundStyle(text.color?.color ?? .primary)
        case .secondary:
            if let color = text.color?.color {
                WidgetSecondaryText(text.text).foregroundStyle(color)
            } else {
                WidgetSecondaryText(text.text)
            }
        case .caption:
            Text(text.text)
                .font(.system(size: WidgetMetrics.secondaryFontSize(for: iconSize) * 0.85, weight: .medium))
                .foregroundStyle(text.color?.color ?? .tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    private func numberView(_ number: ScriptedNumber) -> some View {
        VStack(alignment: edge.isVertical ? .center : .leading, spacing: 0) {
            WidgetPrimaryText(Self.format(number)).foregroundStyle(number.color?.color ?? .primary)
            if let label = number.label {
                WidgetSecondaryText(label)
            }
        }
    }

    @ViewBuilder
    private func progressView(_ progress: ScriptedProgress) -> some View {
        let color = progress.color?.color ?? .blue
        switch progress.style {
        case .ring:
            let ringSize = iconSize * 0.6
            WidgetRing(fraction: progress.fraction, color: color, lineWidth: max(2.5, iconSize * 0.07))
                .frame(width: ringSize, height: ringSize)
                .overlay {
                    if let label = progress.label {
                        Text(label)
                            .font(.system(size: ringSize * 0.34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(ringSize * 0.16)
                    }
                }
        case .bar:
            VStack(alignment: .leading, spacing: iconSize * 0.05) {
                if let label = progress.label {
                    WidgetSecondaryText(label)
                }
                ScriptedBar(fraction: progress.fraction, color: color)
                    .frame(width: iconSize * 1.2, height: max(3, iconSize * 0.08))
            }
        }
    }

    private func children(_ group: ScriptedGroup) -> some View {
        ForEach(Array(group.children.enumerated()), id: \.offset) { _, child in
            ScriptedElementView(element: child)
        }
    }

    /// Spacing in icon widths, as the script wrote it, or the default fraction.
    private func spacing(_ group: ScriptedGroup, default fraction: Double) -> CGFloat {
        CGFloat(iconSize * min(max(group.spacing ?? fraction, 0), 1))
    }

    private static func symbolScale(_ size: ScriptedSize) -> Double {
        switch size {
        case .small: 0.3
        case .regular: 0.46
        case .large: 0.6
        }
    }

    /// The number in the user's locale, with the unit right after it: "12.5 %", "3 km".
    static func format(_ number: ScriptedNumber) -> String {
        let digits = number.fractionDigits.map { min(max($0, 0), 6) }
        let text = number.value.formatted(.number.precision(.fractionLength(digits.map { $0 ... $0 } ?? 0 ... 2)))
        guard let unit = number.unit, !unit.isEmpty else { return text }
        return text + unit
    }
}

/// A horizontal progress bar: a faint track with a rounded fill from the left.
struct ScriptedBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.22))
                Capsule().fill(color).frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .animation(.easeOut(duration: 0.3), value: fraction)
    }
}

extension ScriptedColor {
    var color: Color {
        switch self {
        case let .named(named): named.color
        case let .hex(hex): Color(hex: hex)
        }
    }
}

extension ScriptedNamedColor {
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        case .gray: .gray
        case .primary: .primary
        case .secondary: .secondary
        }
    }
}

extension ScriptedAlignment {
    var horizontal: HorizontalAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}
