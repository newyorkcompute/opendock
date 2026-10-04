import SwiftUI

/// The standard "pill" container for a widget: a rounded, slightly darker
/// surface whose height tracks the dock icon size. Widgets wrap their content in
/// this so every tile in the dock looks like it belongs together.
public struct WidgetTile<Content: View>: View {
    @Environment(\.dockIconSize) private var iconSize

    private let minWidth: Double?
    private let content: Content

    public init(minWidth: Double? = nil, @ViewBuilder content: () -> Content) {
        self.minWidth = minWidth
        self.content = content()
    }

    public var body: some View {
        let radius = WidgetMetrics.cornerRadius(for: iconSize)
        content
            .padding(.horizontal, WidgetMetrics.horizontalPadding(for: iconSize))
            .frame(minWidth: minWidth.map { CGFloat($0) })
            .frame(height: iconSize)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Text styles that scale with the dock. Use these instead of fixed fonts so
/// the icon-size slider resizes widgets coherently.
public struct WidgetPrimaryText: View {
    @Environment(\.dockIconSize) private var iconSize
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .font(.system(size: WidgetMetrics.primaryFontSize(for: iconSize), weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
    }
}

public struct WidgetSecondaryText: View {
    @Environment(\.dockIconSize) private var iconSize
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .font(.system(size: WidgetMetrics.secondaryFontSize(for: iconSize), weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
