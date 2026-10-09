import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// The in-dock reminders tile: a mini list icon in the list's color, the number of reminders
/// waiting, and the list's name.
struct RemindersTileView: View {
    let instance: WidgetInstance

    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.dockEdge) private var edge
    @Environment(\.dockIsVisible) private var isVisible
    @Environment(\.widgetsMayRequestAccess) private var mayRequestAccess
    @State private var service = RemindersService.shared

    private var settings: RemindersSettings { RemindersSettings(instance: instance) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: isVisible ? 60 : 900)) { context in
            let list = settings.list(in: service.lists)
            WidgetTile {
                WidgetStack(spacing: iconSize * (edge.isVertical ? 0.08 : 0.16)) {
                    RemindersListIcon(color: list.map { Color(hex: $0.colorHex) } ?? .blue, size: iconSize * 0.72)
                    summary(list: list, at: context.date)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tileAccessibilityLabel(list: list, at: context.date))
        }
        .task(id: mayRequestAccess) {
            if mayRequestAccess { await service.requestAccessIfNeeded() }
        }
        .task(id: isVisible) {
            if isVisible { await service.autoRefresh() }
        }
    }

    // MARK: Summary (beside the icon on the bottom edge, under it on a side edge)

    private var textAlignment: HorizontalAlignment { edge.isVertical ? .center : .leading }

    @ViewBuilder
    private func summary(list: ReminderList?, at now: Date) -> some View {
        let name = list?.title ?? "Reminders"
        VStack(alignment: textAlignment, spacing: 0) {
            if service.isDenied {
                WidgetPrimaryText(name)
                WidgetSecondaryText("No access")
            } else if !service.hasAccess {
                WidgetPrimaryText(name)
                WidgetSecondaryText("Tap to allow")
            } else {
                WidgetPrimaryText(String(count(list: list, at: now)))
                if settings.showListName {
                    WidgetSecondaryText(name)
                }
            }
        }
        .frame(
            maxWidth: edge.isVertical ? nil : CGFloat(iconSize * 1.8),
            alignment: Alignment(horizontal: textAlignment, vertical: .center))
    }

    private func count(list: ReminderList?, at now: Date) -> Int {
        settings.items(from: service.reminders, lists: service.lists, at: now).count
    }

    private func tileAccessibilityLabel(list: ReminderList?, at now: Date) -> String {
        let name = list?.title ?? "Reminders"
        guard service.hasAccess else { return "\(name), reminders access not allowed" }
        let count = count(list: list, at: now)
        let what = settings.scope == .today ? "due today" : "to do"
        return "\(count) \(count == 1 ? "reminder" : "reminders") \(what) in \(name)"
    }
}

/// A miniature Reminders.app icon: three bulleted rows in the list's color.
struct RemindersListIcon: View {
    let color: Color
    let size: Double

    var body: some View {
        let radius = size * 0.22
        VStack(alignment: .leading, spacing: size * 0.1) {
            ForEach(0 ..< 3) { row in
                HStack(spacing: size * 0.08) {
                    Circle()
                        .fill(color)
                        .frame(width: size * 0.16, height: size * 0.16)
                    Capsule()
                        .fill(Color.black.opacity(0.25))
                        .frame(width: size * (0.44 - Double(row) * 0.08), height: size * 0.07)
                }
            }
        }
        .padding(.leading, size * 0.16)
        .frame(width: size, height: size, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityHidden(true)
    }
}
