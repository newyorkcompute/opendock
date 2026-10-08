import DockCore
import SwiftUI

/// The standard "pill" container for a widget: a rounded, slightly darker
/// surface whose height tracks the dock icon size. Widgets wrap their content in
/// this so every tile in the dock looks like it belongs together.
///
/// On a side edge the dock is a column an icon wide, so the tile is an icon wide instead
/// and as tall as its content needs (at least an icon). Content should stack vertically
/// there (see `WidgetStack`) and let its text shrink to fit (`WidgetPrimaryText` and
/// `WidgetSecondaryText` do).
public struct WidgetTile<Content: View>: View {
    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.dockWidgetScale) private var scale
    @Environment(\.dockEdge) private var edge

    private let minWidth: Double?
    private let content: Content

    /// - Parameter minWidth: The tile's least length along the dock, so it doesn't change
    ///   size as its content does: its width on the bottom edge, its height on a side.
    public init(minWidth: Double? = nil, @ViewBuilder content: () -> Content) {
        self.minWidth = minWidth
        self.content = content()
    }

    public var body: some View {
        let radius = WidgetMetrics.cornerRadius(for: iconSize)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        sized
            .background(
                shape.fill(.primary.opacity(0.06))
                    .overlay(shape.strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
            )
            .clipShape(shape)
    }

    @ViewBuilder
    private var sized: some View {
        let minLength = minWidth.map { CGFloat($0 * scale) }
        if edge.isVertical {
            content
                .padding(.vertical, WidgetMetrics.verticalPadding(for: iconSize))
                .padding(.horizontal, WidgetMetrics.compactHorizontalPadding(for: iconSize))
                .frame(width: iconSize)
                .frame(minHeight: max(CGFloat(iconSize), minLength ?? 0))
        } else {
            content
                .padding(.horizontal, WidgetMetrics.horizontalPadding(for: iconSize))
                .frame(minWidth: minLength)
                .frame(height: iconSize)
        }
    }
}

/// Lines its content up along the bottom edge and stacks it on a side edge, where the
/// dock is a column an icon wide. Use it for a tile's top-level arrangement.
public struct WidgetStack<Content: View>: View {
    @Environment(\.dockEdge) private var edge

    private let spacing: CGFloat?
    private let content: Content

    public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        let layout =
            edge.isVertical
            ? AnyLayout(VStackLayout(spacing: spacing)) : AnyLayout(HStackLayout(spacing: spacing))
        layout { content }
    }
}

/// Text styles that scale with the dock. Use these instead of fixed fonts so
/// the icon-size slider resizes widgets coherently. The text shrinks, to half its size
/// at most, when a tile is too narrow for it (on a side edge).
public struct WidgetPrimaryText: View {
    @Environment(\.dockIconSize) private var iconSize
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .font(.system(size: WidgetMetrics.primaryFontSize(for: iconSize), weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
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
            .minimumScaleFactor(0.5)
    }
}
