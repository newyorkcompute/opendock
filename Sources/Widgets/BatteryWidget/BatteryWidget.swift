import DockCore
import DockWidgetKit
import SwiftUI

public enum BatteryWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.battery
    public static let displayName = "Battery"
    public static let systemImage = "battery.75percent"
    public static let summary = "Charge level and power source."

    public static func makeView(instance: WidgetInstance) -> AnyView {
        AnyView(BatteryTileView(instance: instance))
    }
}

struct BatteryTileView: View {
    let instance: WidgetInstance

    var body: some View {
        WidgetTile {
            WidgetPrimaryText("—%")
        }
    }
}
