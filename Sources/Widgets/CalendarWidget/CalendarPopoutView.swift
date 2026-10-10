import AppKit
import DockWidgetKit
import SwiftUI
import SystemServices

/// Today's agenda, shown when the calendar tile is clicked.
struct CalendarPopoutView: View {
    @State private var service = CalendarService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.headline)

            content

            Divider()

            HStack {
                Button("Open Calendar") { SystemApp.calendar.open() }
                    .disabled(!SystemApp.calendar.isInstalled)
                if service.isUndetermined {
                    Button("Allow Calendar Access") {
                        Task { await service.requestAccess() }
                    }
                } else if service.isDenied {
                    Button("Open Privacy Settings") { SystemSettingsPane.calendars.open() }
                }
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .onAppear { service.refresh(force: true) }
    }

    @ViewBuilder
    private var content: some View {
        if service.isUndetermined {
            Text("Allow access to see your upcoming events here.")
                .foregroundStyle(.secondary)
        } else if service.isDenied {
            Text("Calendar access is turned off. Enable it in System Settings › Privacy & Security › Calendars.")
                .foregroundStyle(.secondary)
        } else if !service.hasAccess {
            Text("OpenDock needs full calendar access to show events.")
                .foregroundStyle(.secondary)
        } else if service.todayEvents.isEmpty {
            Label("Nothing scheduled today", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(service.todayEvents) { event in
                        EventRow(event: event)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct EventRow: View {
    let event: EventSummary

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color(hex: event.calendarColorHex))
                .frame(width: 8, height: 8)
                .padding(.top, 5)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).lineLimit(2)
                Text(timeRange).font(.caption).foregroundStyle(.secondary)
                if !event.calendarTitle.isEmpty {
                    Text(event.calendarTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let location = event.location, event.conferenceURL == nil {
                    Text(location).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                WidgetAccessibility.phrase([event.title, timeRange, event.calendarTitle, event.location ?? ""])
            )

            Spacer(minLength: 8)

            if let url = event.conferenceURL {
                Button("Join") { NSWorkspace.shared.open(url) }
                    .controlSize(.small)
            }
        }
        .opacity(event.isAllDay || event.endDate > .now ? 1 : 0.5)
    }

    private var timeRange: String {
        let range: String
        if event.isAllDay {
            range = "All day"
        } else {
            let start = event.startDate.formatted(date: .omitted, time: .shortened)
            let end = event.endDate.formatted(date: .omitted, time: .shortened)
            range = "\(start) – \(end)"
        }
        if !event.isAllDay, event.endDate <= .now { return "\(range), ended" }
        return range
    }
}
