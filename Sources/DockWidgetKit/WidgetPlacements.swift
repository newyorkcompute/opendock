import DockCore
import Foundation

/// Where one widget type's instances are in the layout, handed to
/// `DockWidget.placementsChanged(_:)`. Equatable, so the observer only calls a widget when
/// something it's given has changed.
public struct WidgetPlacements: Equatable {
    /// One placed instance.
    public struct Placement: Equatable {
        /// The dock item's ID: what `\.widgetUpdateSettings.id` is inside the tile, and the
        /// key to use for any live state the widget keeps for the instance.
        public let id: DockItem.ID
        public let instance: WidgetInstance
        /// Persists changed settings for this instance, like `\.widgetUpdateSettings` does
        /// for its views.
        public let updater: WidgetSettingsUpdater

        public init(id: DockItem.ID, instance: WidgetInstance, updater: WidgetSettingsUpdater) {
            self.id = id
            self.instance = instance
            self.updater = updater
        }
    }

    /// The instances in the active profile, in dock order. Whether or not their tiles are
    /// on screen right now, these are the ones that should be doing something.
    public var active: [Placement]
    /// The item IDs of every instance of the widget, in every profile. Live state keyed by
    /// an ID that isn't here belongs to an item that was removed.
    public var allIDs: Set<DockItem.ID>
    /// Whether a widget may ask for a permission on its own right now; the same as
    /// `\.widgetsMayRequestAccess`. Asking because the user did something is always fine.
    public var mayRequestAccess: Bool

    public init(active: [Placement] = [], allIDs: Set<DockItem.ID> = [], mayRequestAccess: Bool) {
        self.active = active
        self.allIDs = allIDs
        self.mayRequestAccess = mayRequestAccess
    }

    /// Every widget type's placements in `document`, by type ID. Types with no instance
    /// anywhere aren't listed. `updater` builds the settings updater for an item of the
    /// active profile.
    public static func byType(
        in document: DockDocument, mayRequestAccess: Bool, updater: (DockItem) -> WidgetSettingsUpdater
    ) -> [String: WidgetPlacements] {
        var byType: [String: WidgetPlacements] = [:]
        for profile in document.profiles {
            for item in profile.items {
                guard let instance = item.widgetInstance else { continue }
                byType[instance.typeID, default: WidgetPlacements(mayRequestAccess: mayRequestAccess)]
                    .allIDs.insert(item.id)
            }
        }
        for item in document.activeProfile.items {
            guard let instance = item.widgetInstance else { continue }
            byType[instance.typeID]?.active.append(Placement(id: item.id, instance: instance, updater: updater(item)))
        }
        return byType
    }
}
