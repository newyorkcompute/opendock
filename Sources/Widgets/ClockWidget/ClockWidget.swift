import DockCore
import DockWidgetKit
import SwiftUI

public enum ClockWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.clock
    public static let displayName = "Clock"
    public static let systemImage = "clock"
    public static let summary = "The current time and date."

    public static func makeView(instance: WidgetInstance) -> AnyView {
        AnyView(ClockTileView(instance: instance))
    }
}

struct ClockTileView: View {
    let instance: WidgetInstance

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            WidgetTile {
                VStack(alignment: .leading, spacing: 0) {
                    WidgetPrimaryText(context.date.formatted(date: .omitted, time: .shortened))
                    WidgetSecondaryText(context.date.formatted(.dateTime.weekday(.abbreviated).day()))
                }
            }
        }
    }
}
