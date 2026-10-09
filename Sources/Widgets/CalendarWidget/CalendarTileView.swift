import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// The in-dock calendar tile: a mini date icon and, optionally, the next event.
struct CalendarTileView: View {
    let instance: WidgetInstance

    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.dockEdge) private var edge
    @Environment(\.dockIsVisible) private var isVisible
    @Environment(\.widgetsMayRequestAccess) private var mayRequestAccess
    @State private var service = CalendarService.shared

    var body: some View {
        Group {
            if CalendarSettings.showNextEvent.boolValue(in: instance.settings) {
                WidgetTicking(interval: 60) { now in
                    WidgetTile {
                        WidgetStack(spacing: iconSize * (edge.isVertical ? 0.08 : 0.16)) {
                            CalendarDateIcon(date: now, size: iconSize * 0.72)
                            summary(at: now)
                        }
                    }
                }
            } else {
                WidgetTicking(interval: 60) { now in
                    CalendarDateIcon(date: now, size: iconSize)
                }
            }
        }
        .task(id: mayRequestAccess) {
            if mayRequestAccess { await service.requestAccessIfNeeded() }
        }
        .task(id: isVisible) {
            if isVisible { await service.autoRefresh() }
        }
    }

    // MARK: Summary (beside the date on the bottom edge, under it on a side edge)

    private var textAlignment: HorizontalAlignment { edge.isVertical ? .center : .leading }

    @ViewBuilder
    private func summary(at now: Date) -> some View {
        if !service.hasAccess {
            VStack(alignment: textAlignment, spacing: 0) {
                WidgetPrimaryText(now.formatted(.dateTime.month(.abbreviated).day()))
                WidgetSecondaryText("Tap to allow")
            }
        } else if let event = service.nextEvent(at: now) {
            VStack(alignment: textAlignment, spacing: 1) {
                HStack(spacing: iconSize * 0.07) {
                    Circle()
                        .fill(Color(hex: event.calendarColorHex))
                        .frame(width: iconSize * 0.14, height: iconSize * 0.14)
                    Text(event.title)
                        .font(.system(size: WidgetMetrics.secondaryFontSize(for: iconSize) * 1.2, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                WidgetSecondaryText(Self.timeText(for: event, now: now))
            }
            .frame(
                maxWidth: edge.isVertical ? nil : CGFloat(iconSize * 1.8),
                alignment: Alignment(horizontal: textAlignment, vertical: .center))
        } else {
            VStack(alignment: textAlignment, spacing: 0) {
                WidgetPrimaryText(now.formatted(.dateTime.month(.abbreviated).day()))
                WidgetSecondaryText("No more events")
            }
        }
    }

    /// "now", "in 25 min", or a clock time.
    static func timeText(for event: EventSummary, now: Date) -> String {
        if event.isInProgress(at: now) { return "now" }
        let minutes = Int((event.startDate.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 1 { return "in 1 min" }
        if minutes < 60 { return "in \(minutes) min" }
        return event.startDate.formatted(date: .omitted, time: .shortened)
    }
}

/// A miniature Calendar.app icon: red weekday over a large day number.
struct CalendarDateIcon: View {
    let date: Date
    let size: Double

    var body: some View {
        let radius = size * 0.22
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.system(size: size * 0.2, weight: .bold))
                .foregroundStyle(.red)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: size * 0.52, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 2)
        .frame(width: size, height: size)
        .background(.white, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
    }
}
