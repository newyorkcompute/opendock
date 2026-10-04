import DockCore
import DockWidgetKit
import SwiftUI

public enum CalendarWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.calendar
    public static let displayName = "Calendar"
    public static let systemImage = "calendar"
    public static let summary = "Today's date and your next event."

    public static func makeView(instance: WidgetInstance) -> AnyView {
        AnyView(CalendarTileView(instance: instance))
    }
}

struct CalendarTileView: View {
    let instance: WidgetInstance

    var body: some View {
        WidgetTile {
            WidgetPrimaryText(Date.now.formatted(.dateTime.day()))
        }
    }
}
