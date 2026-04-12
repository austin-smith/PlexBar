import Foundation
import Observation

@MainActor
@Observable
final class PlexSessionStore {
    private let settings: PlexSettingsStore
    private let client: PlexAPIClient
    private var pollingTask: Task<Void, Never>?

    var sessions: [PlexSession] = []
    var isLoading = false
    var errorMessage: String?
    var lastUpdated: Date?

    init(settings: PlexSettingsStore, client: PlexAPIClient = PlexAPIClient()) {
        self.settings = settings
        self.client = client
        startPolling()
    }

    var activeStreamCount: Int {
        sessions.count
    }

    func refreshNow() {
        Task {
            await refresh()
        }
    }

    private func startPolling() {
        guard pollingTask == nil else {
            return
        }

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }

                await self.refresh()

                do {
                    try await Task.sleep(for: AppConstants.defaultPollInterval)
                } catch {
                    return
                }
            }
        }
    }

    private func refresh() async {
        guard settings.hasValidConfiguration else {
            sessions = []
            errorMessage = nil
            isLoading = false
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
                clientIdentifier: settings.clientIdentifier
            )

            sessions = try await client.fetchSessions(using: configuration)
            errorMessage = nil
            lastUpdated = Date()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isLoading = false
    }
}
