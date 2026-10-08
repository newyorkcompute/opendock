import DockCore
import DockShell
import Observation

/// Profile commands for the menu bar menu and Settings. Switches go through the dock, so
/// they animate (and show a hidden dock for a moment); before the dock has started they
/// just change the store.
@Observable
final class ProfileSwitcher {
    let store: DockStore
    @ObservationIgnored weak var dock: DockController?

    init(store: DockStore) {
        self.store = store
    }

    func select(_ id: DockProfile.ID) {
        if let dock {
            dock.switchProfile(to: id)
        } else {
            store.selectProfile(id)
        }
    }

    /// Switches to the profile `offset` places along the list, wrapping around.
    func step(by offset: Int) {
        if let dock {
            dock.switchProfile(by: offset)
        } else {
            store.selectProfile(store.document.profileID(offsetFromActive: offset))
        }
    }

    /// Adds an empty profile and switches to it, ready to be filled.
    func create() {
        select(store.addProfile())
    }

    /// Copies a profile and switches to the copy.
    func duplicate(_ id: DockProfile.ID) {
        guard let copy = store.duplicateProfile(id) else { return }
        select(copy)
    }

    func delete(_ id: DockProfile.ID) {
        if id == store.activeProfileID {
            // Switch first, so the dock animates to the profile that takes this one's place.
            var document = store.document
            if document.deleteProfile(id) { select(document.activeProfileID) }
        }
        store.deleteProfile(id)
    }
}
