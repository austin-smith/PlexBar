import Foundation
import Observation

@MainActor
@Observable
final class PlexLibraryStore {
    private let settings: PlexSettingsStore
    private let client: PlexAPIClient

    var libraries: [PlexLibrary] = []
    var isLoading = false
    var errorMessage: String?
    var lastUpdated: Date?

    init(settings: PlexSettingsStore, client: PlexAPIClient = PlexAPIClient()) {
        self.settings = settings
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
        guard settings.hasValidConfiguration else {
            libraries = []
            errorMessage = nil
            isLoading = false
            lastUpdated = nil
            return
        }

        isLoading = true

        do {
            guard let serverURL = settings.normalizedServerURL else {
                throw PlexAPIError.invalidServerURL
            }

            let configuration = PlexConnectionConfiguration(
                serverURL: serverURL,
                token: settings.trimmedServerToken,
                clientContext: PlexClientContext(clientIdentifier: settings.clientIdentifier)
            )

            libraries = try await client.fetchLibraries(using: configuration)
            errorMessage = nil
            lastUpdated = Date()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isLoading = false
    }
}
