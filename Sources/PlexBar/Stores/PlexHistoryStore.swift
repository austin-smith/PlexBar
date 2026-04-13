import Foundation
import Observation

@MainActor
@Observable
final class PlexHistoryStore {
    static let historyWindowDays = 30

    private let settings: PlexSettingsStore
    private let client: PlexAPIClient
    private var pollingTask: Task<Void, Never>?

    var recentItems: [PlexHistoryItem] = []
    var seriesByEpisodeID: [String: PlexHistorySeriesIdentity] = [:]
    var accountsByID: [Int: PlexAccount] = [:]
    var isLoading = false
    var errorMessage: String?
    var lastUpdated: Date?

    init(settings: PlexSettingsStore, client: PlexAPIClient = PlexAPIClient()) {
        self.settings = settings
        self.client = client
        startPolling()
    }

    var topTitleEntries: [PlexTopChartEntry] {
        PlexHistoryAnalytics.topTitleEntries(
            from: recentItems,
            accountsByID: accountsByID,
            seriesByEpisodeID: seriesByEpisodeID,
            limit: 5
        )
    }

    var topTypeEntries: [PlexTopChartEntry] {
        PlexHistoryAnalytics.topTypeEntries(from: recentItems, accountsByID: accountsByID, limit: 4)
    }

    var totalPlayCount: Int {
        recentItems.count
    }

    var historyWindowLabel: String {
        "Last \(Self.historyWindowDays) days"
    }

    func refreshNow() {
        Task {
            await refresh()
        }
    }

    func restartPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        startPolling()
    }

    private func startPolling() {
        guard pollingTask == nil else {
            return
        }

        let pollIntervalDuration = settings.historyPollIntervalDuration

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }

                await self.refresh()

                do {
                    try await Task.sleep(for: pollIntervalDuration)
                } catch {
                    return
                }
            }
        }
    }

    private func refresh() async {
        guard settings.hasValidConfiguration else {
            recentItems = []
            seriesByEpisodeID = [:]
            accountsByID = [:]
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
                clientContext: PlexClientContext(clientIdentifier: settings.clientIdentifier)
            )
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -Self.historyWindowDays, to: Date()) ?? Date.distantPast

            async let historyTask = client.fetchHistory(using: configuration, since: cutoffDate)
            async let accountsTask = client.fetchAccounts(using: configuration)

            let recentItems = try await historyTask
            let seriesByEpisodeID = try await client.fetchHistorySeriesIdentities(
                using: configuration,
                episodeIDs: recentItems.compactMap(\.episodeMetadataItemID)
            )

            self.recentItems = recentItems
            self.seriesByEpisodeID = seriesByEpisodeID

            do {
                let accounts = try await accountsTask
                accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
            } catch {
                accountsByID = [:]
            }

            errorMessage = nil
            lastUpdated = Date()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isLoading = false
    }
}
