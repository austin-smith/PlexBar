import Foundation
import Observation

@MainActor
@Observable
final class PlexHistoryStore {
    static let historyWindowDays = 30

    private let connectionStore: PlexConnectionStore
    private let libraryStore: PlexLibraryStore
    private let client: PlexAPIClient
    private var pollingTask: Task<Void, Never>?

    var recentItems: [PlexHistoryItem] = []
    var seriesByEpisodeID: [String: PlexHistorySeriesIdentity] = [:]
    var accountsByID: [Int: PlexAccount] = [:]
    var isLoading = false
    var errorMessage: String?
    var lastUpdated: Date?

    init(
        connectionStore: PlexConnectionStore,
        libraryStore: PlexLibraryStore,
        client: PlexAPIClient = PlexAPIClient()
    ) {
        self.connectionStore = connectionStore
        self.libraryStore = libraryStore
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

    var topUserEntries: [PlexUserActivityEntry] {
        PlexHistoryAnalytics.topUserEntries(from: recentItems, accountsByID: accountsByID, limit: 5)
    }

    var recentViewerEntries: [PlexUserActivityEntry] {
        PlexHistoryAnalytics.recentViewerEntries(from: recentItems, accountsByID: accountsByID, limit: 6)
    }

    var distinctViewerCount: Int {
        Set(recentItems.compactMap(\.accountID)).count
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
            libraryStore.refreshNow()
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

        let pollIntervalDuration = connectionStore.settings.historyPollIntervalDuration

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }

                await self.refresh()
                self.libraryStore.refreshNow()

                do {
                    try await Task.sleep(for: pollIntervalDuration)
                } catch {
                    return
                }
            }
        }
    }

    private func refresh() async {
        guard connectionStore.settings.hasValidConfiguration else {
            recentItems = []
            seriesByEpisodeID = [:]
            accountsByID = [:]
            errorMessage = nil
            isLoading = false
            return
        }

        isLoading = true

        do {
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -Self.historyWindowDays, to: Date()) ?? Date.distantPast
            let result = try await connectionStore.perform { configuration in
                async let historyTask = client.fetchHistory(using: configuration, since: cutoffDate)
                async let accountsTask = client.fetchAccounts(using: configuration)

                let rawHistoryItems = try await historyTask
                let seriesByEpisodeID = try await client.fetchHistorySeriesIdentities(
                    using: configuration,
                    episodeIDs: rawHistoryItems.compactMap(\.episodeMetadataItemID)
                )

                let accounts: [PlexAccount]
                do {
                    accounts = try await accountsTask
                } catch {
                    accounts = []
                }

                return (rawHistoryItems, seriesByEpisodeID, accounts)
            }

            self.recentItems = PlexHistoryAnalytics.groupedWatchItems(from: result.0)
            self.seriesByEpisodeID = result.1
            self.accountsByID = Dictionary(uniqueKeysWithValues: result.2.map { ($0.id, $0) })

            errorMessage = nil
            lastUpdated = Date()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isLoading = false
    }
}
