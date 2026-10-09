import DockCore
import Foundation
import Observation

/// Tells every registered widget where its instances are (`DockWidget.placementsChanged`)
/// when it starts and after each change to the layout, so a widget with work to do while
/// its tile isn't drawn doesn't depend on the tile's view lifecycle. Each widget is called
/// only when its own placements changed.
public final class WidgetPlacementObserver {
    private let store: DockStore
    private let registry: WidgetRegistry
    private var last: [String: WidgetPlacements] = [:]

    public init(store: DockStore, registry: WidgetRegistry) {
        self.store = store
        self.registry = registry
    }

    public func start() {
        observe()
    }

    private func observe() {
        let (document, mayRequestAccess) = withObservationTracking {
            (store.document, !store.needsWelcome)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
        let byType = WidgetPlacements.byType(in: document, mayRequestAccess: mayRequestAccess) { [store] item in
            WidgetSettingsUpdater(id: item.id) { [store, item] updated in
                var copy = item
                copy.kind = .widget(updated)
                store.updateItem(copy)
            }
        }
        for widget in registry.widgets {
            let placements = byType[widget.typeID] ?? WidgetPlacements(mayRequestAccess: mayRequestAccess)
            guard placements != last[widget.typeID] else { continue }
            last[widget.typeID] = placements
            widget.placementsChanged(placements)
        }
    }
}
