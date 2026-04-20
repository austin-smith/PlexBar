import Foundation
import Observation

@MainActor
@Observable
final class PlexLibraryStore {
    private let connectionStore: PlexConnectionStore
    private let client: PlexAPIClient

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
            libraries = []
            errorMessage = nil
            isLoading = false
            lastUpdated = nil
            return
        }

        isLoading = true

        do {
            libraries = try await connectionStore.perform { configuration in
                try await client.fetchLibraries(using: configuration)
            }
            errorMessage = nil
            lastUpdated = Date()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isLoading = false
    }
}
