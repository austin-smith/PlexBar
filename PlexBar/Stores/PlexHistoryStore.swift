import PlexModels
import Foundation
import Observation

struct PlexMediaHistoryPresentation {
    fileprivate(set) var items: [PlexHistoryItem] = []
    fileprivate(set) var isLoading = false
    fileprivate(set) var errorMessage: String?
    fileprivate(set) var hasLoaded = false

    var isVisible: Bool {
        isLoading || errorMessage != nil || !items.isEmpty
    }
}

@MainActor
@Observable
final class PlexHistoryStore {
    static let historyWindowDays = 30
    private static let mediaHistoryCacheLimit = 12

    private let connectionStore: PlexConnectionStore
    private let libraryStore: PlexLibraryStore
    private let client: PlexAPIClient
    private var pollingTask: Task<Void, Never>?
    private var mediaHistoryByKey: [MediaHistoryCacheKey: PlexMediaHistoryPresentation] = [:]
    private var mediaHistoryGenerations: [MediaHistoryCacheKey: Int] = [:]
    private var mediaHistoryRecency: [MediaHistoryCacheKey] = []
    private var identityDirectoryAccountScope: String?
    private var refreshGeneration = UUID()

    var recentItems: [PlexHistoryItem] = []
    var seriesByEpisodeID: [String: PlexHistorySeriesIdentity] = [:]
    var accountsByID: [Int: PlexAccount] = [:]
    var devicesByID: [Int: PlexHistoryDevice] = [:]
    var isLoading = false
    var errorMessage: String?
    var lastUpdated: Date?

    init(
        connectionStore: PlexConnectionStore,
        libraryStore: PlexLibraryStore,
        client: PlexAPIClient = PlexAPIClient(),
        startsPolling: Bool = true
    ) {
        self.connectionStore = connectionStore
        self.libraryStore = libraryStore
        self.client = client
        if startsPolling {
            startPolling()
        }
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
        PlexHistoryAnalytics.recentViewerEntries(
            from: recentItems, accountsByID: accountsByID, limit: 6)
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

    func resetServerScopedState() {
        refreshGeneration = UUID()
        recentItems = []
        seriesByEpisodeID = [:]
        accountsByID = [:]
        devicesByID = [:]
        identityDirectoryAccountScope = nil
        mediaHistoryByKey = [:]
        mediaHistoryGenerations = [:]
        mediaHistoryRecency = []
        errorMessage = nil
        isLoading = false
        lastUpdated = nil
    }

    func mediaHistoryPresentation(for item: PlexMediaItem) -> PlexMediaHistoryPresentation? {
        guard let key = mediaHistoryCacheKey(for: item) else {
            return nil
        }

        return mediaHistoryByKey[key] ?? PlexMediaHistoryPresentation()
    }

    func loadMediaHistory(
        for item: PlexMediaItem,
        forceRefresh: Bool = false
    ) async {
        guard let key = mediaHistoryCacheKey(for: item) else {
            return
        }
        prepareIdentityDirectory(for: key.accountScope)

        var presentation = mediaHistoryByKey[key] ?? PlexMediaHistoryPresentation()
        guard forceRefresh || (!presentation.hasLoaded && !presentation.isLoading) else {
            touchMediaHistory(key)
            return
        }

        let generation = (mediaHistoryGenerations[key] ?? 0) + 1
        mediaHistoryGenerations[key] = generation
        presentation.isLoading = true
        presentation.errorMessage = nil
        mediaHistoryByKey[key] = presentation
        touchMediaHistory(key)

        do {
            let cutoffDate = historyCutoffDate()
            let shouldLoadIdentityDirectory = identityDirectoryAccountScope != key.accountScope
            let result = try await connectionStore.perform { configuration in
                async let historyTask = client.fetchHistory(
                    using: configuration,
                    since: cutoffDate,
                    metadataItemID: key.metadataItemID
                )

                let identityDirectory: PlexHistoryIdentityDirectory?
                if shouldLoadIdentityDirectory {
                    identityDirectory = try? await client.fetchHistoryIdentityDirectory(
                        using: configuration
                    )
                } else {
                    identityDirectory = nil
                }

                return (try await historyTask, identityDirectory)
            }

            guard mediaHistoryGenerations[key] == generation else {
                return
            }
            guard mediaHistoryCacheKey(for: item) == key else {
                discardMediaHistory(key)
                return
            }

            if let identityDirectory = result.1 {
                apply(identityDirectory, accountScope: key.accountScope)
            }
            presentation.items = PlexHistoryAnalytics.groupedWatchItems(from: result.0)
            presentation.isLoading = false
            presentation.errorMessage = nil
            presentation.hasLoaded = true
            mediaHistoryByKey[key] = presentation
            touchMediaHistory(key)
        } catch {
            guard mediaHistoryGenerations[key] == generation else {
                return
            }
            guard mediaHistoryCacheKey(for: item) == key else {
                discardMediaHistory(key)
                return
            }

            presentation.isLoading = false
            presentation.errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            presentation.hasLoaded = true
            mediaHistoryByKey[key] = presentation
            touchMediaHistory(key)
        }
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
            resetServerScopedState()
            return
        }

        let generation = UUID()
        refreshGeneration = generation
        isLoading = true
        let selectedAccountScope = connectionStore.accountCacheScope
        prepareIdentityDirectory(for: selectedAccountScope)

        do {
            let cutoffDate = historyCutoffDate()
            let result = try await connectionStore.perform { configuration in
                async let historyTask = client.fetchHistory(using: configuration, since: cutoffDate)
                async let identityDirectoryTask = client.fetchHistoryIdentityDirectory(using: configuration)

                let rawHistoryItems = try await historyTask
                let seriesByEpisodeID = try await client.fetchHistorySeriesIdentities(
                    using: configuration,
                    episodeIDs: rawHistoryItems.compactMap(\.episodeMetadataItemID)
                )

                let identityDirectory: PlexHistoryIdentityDirectory?
                do {
                    identityDirectory = try await identityDirectoryTask
                } catch {
                    identityDirectory = nil
                }

                return (rawHistoryItems, seriesByEpisodeID, identityDirectory)
            }

            guard refreshGeneration == generation else {
                return
            }
            self.recentItems = PlexHistoryAnalytics.groupedWatchItems(from: result.0)
            self.seriesByEpisodeID = result.1
            if let identityDirectory = result.2 {
                apply(identityDirectory, accountScope: selectedAccountScope)
            }

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

    private func mediaHistoryCacheKey(for item: PlexMediaItem) -> MediaHistoryCacheKey? {
        guard item.supportsPlaybackHistory,
            let serverIdentifier = connectionStore.settings.selectedServerIdentifier?.nilIfBlank,
            let metadataItemID = Int(item.ratingKey)
        else {
            return nil
        }

        return MediaHistoryCacheKey(
            accountScope: PlexConnectionConfiguration.accountCacheScope(
                serverIdentifier: serverIdentifier,
                token: connectionStore.settings.trimmedServerToken
            ),
            metadataItemID: metadataItemID
        )
    }

    private func historyCutoffDate() -> Date {
        Calendar.current.date(
            byAdding: .day,
            value: -Self.historyWindowDays,
            to: Date()
        ) ?? Date.distantPast
    }

    private func touchMediaHistory(_ key: MediaHistoryCacheKey) {
        mediaHistoryRecency.removeAll { $0 == key }
        mediaHistoryRecency.append(key)

        while mediaHistoryRecency.count > Self.mediaHistoryCacheLimit {
            let evictedKey = mediaHistoryRecency.removeFirst()
            mediaHistoryByKey.removeValue(forKey: evictedKey)
            mediaHistoryGenerations.removeValue(forKey: evictedKey)
        }
    }

    private func discardMediaHistory(_ key: MediaHistoryCacheKey) {
        mediaHistoryByKey.removeValue(forKey: key)
        mediaHistoryGenerations.removeValue(forKey: key)
        mediaHistoryRecency.removeAll { $0 == key }
    }

    private func prepareIdentityDirectory(for accountScope: String) {
        guard identityDirectoryAccountScope != nil,
            identityDirectoryAccountScope != accountScope
        else {
            return
        }
        accountsByID = [:]
        devicesByID = [:]
        identityDirectoryAccountScope = nil
    }

    private func apply(
        _ identityDirectory: PlexHistoryIdentityDirectory,
        accountScope: String
    ) {
        accountsByID = Dictionary(uniqueKeysWithValues: identityDirectory.accounts.map { ($0.id, $0) })
        devicesByID = Dictionary(uniqueKeysWithValues: identityDirectory.devices.map { ($0.id, $0) })
        identityDirectoryAccountScope = accountScope
    }

    private struct MediaHistoryCacheKey: Hashable {
        let accountScope: String
        let metadataItemID: Int
    }
}
