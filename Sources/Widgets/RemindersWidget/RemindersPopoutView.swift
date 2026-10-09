import AppKit
import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// The tile's reminders, grouped by when they're due, each with a circle to tick it off.
struct RemindersPopoutView: View {
    let instance: WidgetInstance

    @State private var service = RemindersService.shared
    /// Reminders ticked but not yet saved, so the check shows before the row disappears.
    @State private var completing: Set<String> = []

    private var settings: RemindersSettings { RemindersSettings(instance: instance) }

    var body: some View {
        let now = service.lastRefresh
        let list = settings.list(in: service.lists)
        let items = settings.items(from: service.reminders, lists: service.lists, at: now)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(list?.title ?? "Reminders")
                    .font(.headline)
                    .foregroundStyle(list.map { Color(hex: $0.colorHex) } ?? .primary)
                Spacer()
                if service.hasAccess, !items.isEmpty {
                    Text(String(items.count))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }

            content(items: items, at: now)

            Divider()

            HStack {
                Button("Open Reminders") {
                    NSWorkspace.shared.openApplication(
                        at: URL(fileURLWithPath: "/System/Applications/Reminders.app"),
                        configuration: NSWorkspace.OpenConfiguration()
                    )
                }
                if service.isUndetermined {
                    Button("Allow Reminders Access") {
                        Task { await service.requestAccess() }
                    }
                } else if service.isDenied {
                    Button("Open Privacy Settings") {
                        if let url = URL(
                            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")
                        {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .onAppear { service.refresh(force: true) }
    }

    @ViewBuilder
    private func content(items: [ReminderItem], at now: Date) -> some View {
        if service.isUndetermined {
            Text("Allow access to see your reminders here.")
                .foregroundStyle(.secondary)
        } else if service.isDenied {
            Text("Reminders access is turned off. Enable it in System Settings › Privacy & Security › Reminders.")
                .foregroundStyle(.secondary)
        } else if !service.hasAccess {
            Text("OpenDock needs full reminders access to show reminders.")
                .foregroundStyle(.secondary)
        } else if items.isEmpty {
            Label(settings.scope == .today ? "Nothing due today" : "All done", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ReminderAgenda.sections(items, at: now)) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(section.state == .overdue ? Color.red : Color.secondary)
                            ForEach(section.items) { item in
                                ReminderRow(
                                    item: item,
                                    isOverdue: section.state == .overdue,
                                    isCompleting: completing.contains(item.id),
                                    now: now
                                ) {
                                    complete(item)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.default, value: items)
            }
            .frame(maxHeight: 320)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Shows the check for a moment, then saves, so the row doesn't vanish under the pointer.
    private func complete(_ item: ReminderItem) {
        guard !completing.contains(item.id) else { return }
        completing.insert(item.id)
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            service.complete(item)
            completing.remove(item.id)
        }
    }
}

private struct ReminderRow: View {
    let item: ReminderItem
    let isOverdue: Bool
    let isCompleting: Bool
    let now: Date
    let complete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: complete) {
                ZStack {
                    Circle()
                        .strokeBorder(color, lineWidth: 1.5)
                    if isCompleting {
                        Circle()
                            .fill(color)
                            .padding(3)
                    }
                }
                .frame(width: 18, height: 18)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 1)
            .accessibilityLabel(isCompleting ? "Completed" : "Complete \(item.title)")
            .disabled(isCompleting)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if let marks = priorityMarks {
                        Text(marks)
                            .foregroundStyle(color)
                            .fontWeight(.semibold)
                    }
                    Text(item.title).lineLimit(2)
                }
                if let due = ReminderAgenda.dueDescription(for: item, at: now) {
                    Text(due)
                        .font(.caption)
                        .foregroundStyle(isOverdue ? Color.red : Color.secondary)
                }
                if let notes = item.notes {
                    Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .opacity(isCompleting ? 0.5 : 1)
    }

    private var color: Color { Color(hex: item.listColorHex) }

    /// Reminders.app's exclamation marks: one to three by priority.
    private var priorityMarks: String? {
        switch item.priority {
        case .high: "!!!"
        case .medium: "!!"
        case .low: "!"
        case .none: nil
        }
    }
}
