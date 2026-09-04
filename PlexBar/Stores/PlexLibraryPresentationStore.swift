import Observation
import SwiftUI

@MainActor
@Observable
final class PlexLibraryPresentationState {
    var navigationPath: [PlexNavigationRoute] = []
    var scrollPosition = ScrollPosition(idType: String.self, edge: .top)
    let searchStore = PlexLibrarySearchStore()
}

@MainActor
@Observable
final class PlexLibraryPresentationStore {
    private(set) var statesByLibraryID: [String: PlexLibraryPresentationState] = [:]

    func state(for libraryID: String) -> PlexLibraryPresentationState? {
        statesByLibraryID[libraryID]
    }

    func synchronize(libraryIDs: [String]) {
        let activeLibraryIDs = Set(libraryIDs)
        statesByLibraryID = statesByLibraryID.filter { activeLibraryIDs.contains($0.key) }

        for libraryID in libraryIDs where statesByLibraryID[libraryID] == nil {
            statesByLibraryID[libraryID] = PlexLibraryPresentationState()
        }
    }

    func removeAll() {
        statesByLibraryID.removeAll()
    }
}
