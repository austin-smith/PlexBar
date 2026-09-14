import PlexModels
import Foundation
import Testing
@testable import PlexBar

@MainActor
struct PlexAccountScopedStateTests {
    @Test func accountChangeResetClearsEveryPublishedServerScopedStore() throws {
        let suiteName = "PlexBarTests.accountChangeResetClearsEveryPublishedServerScopedStore"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let credentials = PlexStoredCredentials(
            userToken: "user-token",
            serverToken: "server-token"
        )
        let settings = PlexSettingsStore(
            defaults: defaults,
            credentialStore: PlexMemoryCredentialStore(credentials: credentials),
            initialCredentials: credentials
        )
        settings.selectedServerIdentifier = "server-id"
        let connectionStore = PlexConnectionStore(settings: settings)
        let libraryStore = PlexLibraryStore(connectionStore: connectionStore)
        let historyStore = PlexHistoryStore(
            connectionStore: connectionStore,
            libraryStore: libraryStore,
            startsPolling: false
        )
        let browserStore = PlexBrowserStore(connectionStore: connectionStore)

        libraryStore.libraries = [sampleLibrary]
        libraryStore.errorMessage = "Old library error"
        libraryStore.lastUpdated = Date()

        historyStore.recentItems = [sampleHistoryItem]
        historyStore.accountsByID = [7: PlexAccount(id: 7, name: "Previous User", thumb: nil)]
        historyStore.errorMessage = "Old history error"
        historyStore.lastUpdated = Date()

        browserStore.homeState.hasLoadedHubs = true
        browserStore.homeState.hubsErrorMessage = "Old home error"
        browserStore.playlistsTotalSize = 1
        browserStore.playlistsErrorMessage = "Old playlist error"
        browserStore.libraryFilterValuesByCacheKey = [
            "old-scope": [
                PlexLibraryFilterValue(
                    filterID: "genre",
                    queryName: "genre",
                    queryValue: "1",
                    title: "Drama"
                )
            ]
        ]

        browserStore.resetServerScopedState()
        libraryStore.resetServerScopedState()
        historyStore.resetServerScopedState()

        #expect(!browserStore.hasLoadedHomeHubs)
        #expect(browserStore.homeHubsErrorMessage == nil)
        #expect(browserStore.playlists.isEmpty)
        #expect(browserStore.playlistsTotalSize == nil)
        #expect(browserStore.playlistsErrorMessage == nil)
        #expect(browserStore.libraryFilterValuesByCacheKey.isEmpty)
        #expect(browserStore.cacheMetrics.libraryRequestCount == 0)

        #expect(libraryStore.libraries.isEmpty)
        #expect(libraryStore.errorMessage == nil)
        #expect(libraryStore.lastUpdated == nil)

        #expect(historyStore.recentItems.isEmpty)
        #expect(historyStore.accountsByID.isEmpty)
        #expect(historyStore.devicesByID.isEmpty)
        #expect(historyStore.errorMessage == nil)
        #expect(historyStore.lastUpdated == nil)
    }

    private var sampleLibrary: PlexLibrary {
        PlexLibrary(
            id: "2",
            title: "Movies",
            type: .movie,
            compositePath: nil,
            artPath: nil,
            thumbPath: nil,
            itemCount: 1,
            secondaryCount: nil,
            secondaryCountLabel: nil,
            updatedAt: nil,
            scannedAt: nil,
            contentChangedAt: nil,
            latestAddedAt: nil,
            latestItemTitle: nil
        )
    }

    private var sampleHistoryItem: PlexHistoryItem {
        PlexHistoryItem(
            historyKey: "/status/sessions/history/1",
            key: "/library/metadata/1",
            ratingKey: "1",
            title: "Previous Account Movie",
            type: "movie",
            thumb: nil,
            parentThumb: nil,
            grandparentThumb: nil,
            art: nil,
            grandparentTitle: nil,
            parentTitle: nil,
            parentIndex: nil,
            index: nil,
            originallyAvailableAt: nil,
            viewedAt: Date(),
            accountID: 7
        )
    }
}
