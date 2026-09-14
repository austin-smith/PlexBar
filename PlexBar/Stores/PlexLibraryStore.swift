import PlexModels
import Foundation
import Observation

@MainActor
@Observable
final class PlexLibraryStore {
    private let connectionStore: PlexConnectionStore
    private let client: PlexAPIClient
    private var refreshGeneration = UUID()

    var libraries: [PlexLibrary] = []
    var isLoading = false
    var errorMessage: String?
    var lastUpdated: Date?

    init(connectionStore: PlexConnectionStore, client: PlexAPIClient = PlexAPIClient()) {
        self.connectionStore = connectionStore
        self.client = client
    }

    var libraryCount: Int {
        libraries.count
    }

    var totalItemCount: Int {
        libraries.reduce(0) { $0 + $1.itemCount }
    }

    func refreshNow() {
        Task {
            await refresh()
        }
    }

    func refresh() async {
        guard connectionStore.settings.hasValidConfiguration else {
            resetServerScopedState()
            return
        }

        let generation = UUID()
        refreshGeneration = generation
        isLoading = true

        do {
            let refreshedLibraries = try await connectionStore.perform { configuration in
                try await client.fetchLibraries(using: configuration)
            }
            guard refreshGeneration == generation else {
                return
            }
            libraries = refreshedLibraries
            errorMessage = nil
            lastUpdated = Date()
        } catch is CancellationError {
            return
        } catch {
            guard refreshGeneration == generation else {
                return
            }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        if refreshGeneration == generation {
            isLoading = false
        }
    }

    func resetServerScopedState() {
        refreshGeneration = UUID()
        libraries = []
        errorMessage = nil
        isLoading = false
        lastUpdated = nil
    }
}
