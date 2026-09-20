import PlexModels
#if os(tvOS)
@testable import PlexTopShelf
@testable import PlexClientKit
import AVFoundation
import Foundation
import Observation
import os
import Synchronization
import Testing
@testable import PlexBarTV

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct TVPlaybackPreparationTests {
    @Test(arguments: ["show", "season"])
    func hierarchyPlaybackLoadsTheServerSelectedEpisodeAndItsResumePosition(type: String) async throws {
        let fixture = try await Fixture(hierarchyType: type)
        defer { fixture.close() }
        let hierarchy = try Self.item(Self.hierarchyJSON(type: type))

        await prepare(hierarchy, in: fixture.store)

        let request = try #require(fixture.store.playbackRequest)
        #expect(request.item.ratingKey == "42")
        #expect(request.item.isPlayable)
        #expect(request.startTime == 123)
        #expect(request.queue?.currentItem.playQueueItemID == "502")
        let queueRequest = try #require(fixture.requests.withLock { $0.first { $0.url?.path == "/provider/queue" } })
        let query = URLComponents(url: queueRequest.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "onDeck", value: "1")))
        #expect(!query.contains { $0.name == "key" })
        #expect(fixture.requests.withLock { $0.contains { $0.url?.path == "/library/metadata/42" } })
    }

    @Test
    func explicitEpisodeRestartPreservesTheSelectedEpisodeAndStartsAtZero() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        let episode = try Self.item(Self.episodeJSON)

        await prepare(episode, in: fixture.store, resume: false)

        let request = try #require(fixture.store.playbackRequest)
        #expect(request.item.ratingKey == "42")
        #expect(request.startTime == 0)
        #expect(request.queue?.currentItem.ratingKey == "42")
        let queueRequest = try #require(fixture.requests.withLock { $0.first { $0.url?.path == "/provider/queue" } })
        let query = URLComponents(url: queueRequest.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "key", value: "/library/metadata/42")))
        #expect(!query.contains { $0.name == "onDeck" })
    }

    @Test
    func episodeHubItemWithoutMediaCanResolveAndResume() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        let seed = try Self.item(#"{"ratingKey":"42","title":"Episode from Home","type":"episode"}"#)
        #expect(!seed.isPlayable)
        #expect(seed.tvCanStartPlayback)

        await prepare(seed, in: fixture.store)

        let request = try #require(fixture.store.playbackRequest)
        #expect(request.item.isPlayable)
        #expect(request.item.ratingKey == "42")
        #expect(request.startTime == 123)
    }

    @Test
    func failedSelectedEpisodeLoadDoesNotPlayAnotherEpisode() async throws {
        let fixture = try await Fixture(selectedEpisodeStatus: 500)
        defer { fixture.close() }
        let show = try Self.item(Self.hierarchyJSON(type: "show"))

        await prepare(show, in: fixture.store)

        #expect(fixture.store.playbackRequest == nil)
        #expect(fixture.store.errorMessage?.contains("500") == true)
        #expect(!fixture.requests.withLock { $0.contains { $0.url?.path == "/library/metadata/41" } })
    }

    @Test
    func watchedStateSuccessWaitsForAcknowledgementAndCoalescesCompletionEvents() async throws {
        let gate = TVTimelineResponseGate()
        let fixture = try await Fixture(watchedStateGate: gate)
        defer { fixture.close() }
        let connection = try #require(fixture.store.connection)
        let update = fixture.store.makeWatchedStateUpdate(for: try Self.item(Self.episodeJSON), connection: connection)
        let revision = fixture.store.playbackMetadataRevision
        let homeCount = fixture.homeRequestCount

        fixture.store.presentPlayback(TVPlexPlaybackRequest(item: update.item, startTime: 0))
        fixture.store.markWatched(update)
        fixture.store.markWatched(update)
        await gate.waitUntilEntered()
        #expect(update.state == .pending)
        #expect(fixture.watchedStateRequests.count == 1)
        #expect(fixture.homeRequestCount == homeCount)
        #expect(fixture.store.playbackMetadataRevision == revision)
        fixture.store.dismissPlayer()
        await gate.release()
        try await waitFor { update.state == .succeeded && !fixture.store.isLoadingHome }

        #expect(fixture.store.playbackMetadataRevision != revision)
        #expect(fixture.homeRequestCount == homeCount + 1)
        fixture.store.markWatched(update)
        #expect(update.state == .succeeded)
        #expect(fixture.watchedStateRequests.count == 1)
        let request = try #require(fixture.watchedStateRequests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.host == "plex.test")
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "key", value: "42")))
        #expect(query.contains(URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library")))
        #expect(fixture.store.watchedStateFailures.isEmpty)
    }

    @Test
    func watchedStateFailureSurvivesAdvancingAndRetriesTheOriginalItemExplicitly() async throws {
        let status = OSAllocatedUnfairLock(initialState: 500)
        let fixture = try await Fixture(watchedStateStatus: status)
        defer { fixture.close() }
        let connection = try #require(fixture.store.connection)
        let firstItem = try Self.item(Self.episodeJSON)
        let nextItem = try Self.item(Self.episodeJSON.replacingOccurrences(of: "42", with: "43"))
        let first = fixture.store.makeWatchedStateUpdate(for: firstItem, connection: connection)
        let revision = fixture.store.playbackMetadataRevision
        let homeCount = fixture.homeRequestCount
        fixture.store.markWatched(first)
        fixture.store.presentPlayback(TVPlexPlaybackRequest(item: nextItem, startTime: 0))
        try await waitFor { first.state == .failed }
        let failure = try #require(fixture.store.watchedStateFailures.first)
        #expect(failure.update === first)
        #expect(failure.message.contains("500"))
        #expect(fixture.store.playbackMetadataRevision == revision)
        #expect(fixture.homeRequestCount == homeCount)
        #expect(fixture.store.errorMessage == nil)
        fixture.store.markWatched(first)
        #expect(first.state == .failed)
        #expect(fixture.watchedStateRequests.count == 1)
        fixture.store.dismissPlayer()
        #expect(fixture.store.watchedStateFailures.first?.id == failure.id)

        fixture.store.retryWatchedStateUpdate(failure)
        try await waitFor { first.state == .failed }
        let repeatedFailure = try #require(fixture.store.watchedStateFailures.first)
        #expect(repeatedFailure.id != failure.id)
        #expect(fixture.homeRequestCount == homeCount)
        #expect(fixture.store.playbackMetadataRevision == revision)

        // Dismissal of the alert and its Retry action may arrive in either order.
        fixture.store.dismissWatchedStateFailure(repeatedFailure)
        status.withLock { $0 = 200 }
        fixture.store.retryWatchedStateUpdate(repeatedFailure)
        fixture.store.retryWatchedStateUpdate(repeatedFailure)
        try await waitFor { first.state == .succeeded && !fixture.store.isLoadingHome }
        #expect(fixture.store.watchedStateFailures.isEmpty)
        let second = fixture.store.makeWatchedStateUpdate(for: nextItem, connection: connection)
        fixture.store.markWatched(second)
        try await waitFor { second.state == .succeeded && !fixture.store.isLoadingHome }
        let keys = fixture.watchedStateRequests.map { request in
            URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "key" }?.value
        }
        #expect(keys == ["42", "42", "42", "43"])
    }

    @Test
    func missingWatchedEndpointSurfacesFailureWithoutRefreshingMetadata() async throws {
        let fixture = try await Fixture(includesScrobbleEndpoint: false)
        defer { fixture.close() }
        let connection = try #require(fixture.store.connection)
        let update = fixture.store.makeWatchedStateUpdate(for: try Self.item(Self.episodeJSON), connection: connection)
        let revision = fixture.store.playbackMetadataRevision
        let homeCount = fixture.homeRequestCount
        fixture.store.markWatched(update)
        try await waitFor { update.state == .failed }
        #expect(fixture.store.watchedStateFailures.first?.message == PlexAPIError.missingLibraryTimelineFeature.localizedDescription)
        #expect(fixture.watchedStateRequests.isEmpty)
        #expect(fixture.store.playbackMetadataRevision == revision)
        #expect(fixture.homeRequestCount == homeCount)
    }

    @Test
    func watchedStateProviderDiscoveryFailurePropagates() async throws {
        let providerStatus = OSAllocatedUnfairLock(initialState: 200)
        let fixture = try await Fixture(providerStatus: providerStatus)
        defer { fixture.close() }
        let connection = try #require(fixture.store.connection)
        providerStatus.withLock { $0 = 503 }
        // A fresh client forces discovery instead of using the connection fixture's cache.
        let client = fixture.makeClient()
        do {
            try await client.markWatched(try Self.item(Self.episodeJSON), connection: connection)
            Issue.record("Provider discovery failure was suppressed.")
        } catch {
            #expect(error.localizedDescription.contains("503"))
        }
        #expect(fixture.watchedStateRequests.isEmpty)
    }

    @Test(arguments: [200, 500])
    func serverSwitchInvalidatesPendingWatchedStateUpdates(status: Int) async throws {
        let gate = TVTimelineResponseGate()
        let fixture = try await Fixture(watchedStateGate: gate, watchedStateStatus: OSAllocatedUnfairLock(initialState: status))
        defer { fixture.close() }
        let connection = try #require(fixture.store.connection)
        let item = try Self.item(Self.episodeJSON)
        let pending = fixture.store.makeWatchedStateUpdate(for: item, connection: connection)
        let notStarted = fixture.store.makeWatchedStateUpdate(for: item, connection: connection)
        fixture.store.markWatched(pending)
        await gate.waitUntilEntered()
        await fixture.selectOtherServer()
        let revision = fixture.store.playbackMetadataRevision
        let homeCount = fixture.homeRequestCount
        fixture.store.markWatched(notStarted)
        #expect(notStarted.state == .invalidated)
        await gate.release()
        try await waitFor { pending.state == .invalidated }
        #expect(fixture.store.watchedStateFailures.isEmpty)
        #expect(fixture.store.playbackMetadataRevision == revision)
        #expect(fixture.homeRequestCount == homeCount)
        #expect(fixture.watchedStateRequests.map { $0.url?.host } == ["plex.test"])
    }

    @Test
    func serverSwitchDiscardsWatchedFailureAndRejectsItsStaleRetry() async throws {
        let fixture = try await Fixture(watchedStateStatus: OSAllocatedUnfairLock(initialState: 500))
        defer { fixture.close() }
        let update = fixture.store.makeWatchedStateUpdate(
            for: try Self.item(Self.episodeJSON), connection: try #require(fixture.store.connection)
        )
        fixture.store.markWatched(update)
        try await waitFor { update.state == .failed }
        let failure = try #require(fixture.store.watchedStateFailures.first)
        await fixture.selectOtherServer()
        #expect(fixture.store.watchedStateFailures.isEmpty)
        fixture.store.retryWatchedStateUpdate(failure)
        #expect(update.state == .invalidated)
        #expect(fixture.watchedStateRequests.map { $0.url?.host } == ["plex.test"])
    }

    @Test
    func metadataRefreshFailureDoesNotUndoSuccessfulWatchedWrite() async throws {
        let homeStatus = OSAllocatedUnfairLock(initialState: 200)
        let fixture = try await Fixture(homeStatus: homeStatus)
        defer { fixture.close() }
        let update = fixture.store.makeWatchedStateUpdate(
            for: try Self.item(Self.episodeJSON), connection: try #require(fixture.store.connection)
        )
        homeStatus.withLock { $0 = 500 }
        fixture.store.markWatched(update)
        try await waitFor { update.state == .succeeded && !fixture.store.isLoadingHome }
        #expect(fixture.store.errorMessage?.contains("500") == true)
        #expect(fixture.store.watchedStateFailures.isEmpty)
        fixture.store.markWatched(update)
        #expect(update.state == .succeeded)
        #expect(fixture.watchedStateRequests.count == 1)
    }

    @Test
    func finalPlaybackReportCompletesBeforeBrowseMetadataIsInvalidated() async throws {
        let gate = TVTimelineResponseGate()
        let fixture = try await Fixture(timelineGate: gate)
        defer { fixture.close() }
        var homeRequests = fixture.homeRequests.makeAsyncIterator()
        _ = await homeRequests.next() // Initial connection load.
        let revision = fixture.store.playbackMetadataRevision
        let connection = try #require(fixture.store.connection)
        fixture.store.dismissPlayer()
        let report = Task {
            await fixture.store.reportPlayback(PlexTimelineUpdate(
                ratingKey: "42", state: .stopped, time: 124_000, duration: 1_800_000,
                sessionIdentifier: "test-session", continuing: false
            ), connection: connection)
        }
        await gate.waitUntilEntered()

        #expect(fixture.store.playbackMetadataRevision == revision)
        #expect(fixture.requests.withLock { $0.filter { $0.url?.path == "/hubs/promoted" }.count } == 1)

        await gate.release()
        _ = await report.value
        #expect(fixture.store.playbackMetadataRevision != revision)
        _ = await homeRequests.next() // Automatic refresh after the report.
    }

    @Test
    func queuedStopKeepsItsConnectionWhenTheSessionIsReusedOnAnotherServer() async throws {
        let gate = TVTimelineResponseGate()
        let fixture = try await Fixture(timelineGate: gate)
        defer { fixture.close() }
        let session = fixture.makePlaybackSession()
        let firstRequest = TVPlexPlaybackRequest(item: try Self.item(Self.episodeJSON), startTime: 0)
        let firstPreparation = Task { await session.prepare(request: firstRequest, store: fixture.store) }
        await gate.waitUntilEntered()
        let firstStop = try #require(session.stop(request: firstRequest))

        await fixture.selectOtherServer()
        let revision = fixture.store.playbackMetadataRevision
        let secondRequest = TVPlexPlaybackRequest(item: try Self.item(Self.episodeJSON), startTime: 123)
        await session.prepare(request: secondRequest, store: fixture.store)
        let secondStop = try #require(session.stop(request: secondRequest))
        await secondStop.value
        #expect(fixture.store.playbackMetadataRevision != revision)
        let secondRevision = fixture.store.playbackMetadataRevision

        await gate.release()
        await firstPreparation.value
        await firstStop.value
        #expect(fixture.store.playbackMetadataRevision == secondRevision)
        let reports = fixture.requests.withLock { $0.filter { $0.url?.path == "/provider/timeline" } }
        #expect(reports.count == 2)
        #expect(reports.map { $0.url?.host } == ["plex.test", "other.plex.test"])
        #expect(reports.last?.value(forHTTPHeaderField: "X-Plex-Session-Identifier") == secondRequest.sessionIdentifier)
    }

    @Test
    func serverSwitchBeforeTheFirstTimelineReportDoesNotRetargetTheFinalStop() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        let session = fixture.makePlaybackSession()
        let request = TVPlexPlaybackRequest(item: try Self.item(Self.episodeJSON), startTime: 123)
        await session.prepare(request: request, store: fixture.store)
        #expect(session.player != nil)
        #expect(!fixture.requests.withLock { $0.contains { $0.url?.path == "/provider/timeline" } })

        await fixture.selectOtherServer()
        let revision = fixture.store.playbackMetadataRevision
        let stop = try #require(session.stop(request: request))
        await stop.value

        #expect(session.player == nil)
        #expect(fixture.store.playbackMetadataRevision == revision)
        #expect(!fixture.requests.withLock { $0.contains { $0.url?.path == "/provider/timeline" } })
    }

    @Test
    func serverSwitchDuringPreparationRejectsTheOldPlaybackPlan() async throws {
        let gate = TVTimelineResponseGate()
        let fixture = try await Fixture(playbackPlanGate: gate)
        defer { fixture.close() }
        let session = fixture.makePlaybackSession()
        let request = TVPlexPlaybackRequest(item: try Self.item(Self.episodeJSON), startTime: 123)
        let preparation = Task { await session.prepare(request: request, store: fixture.store) }
        await gate.waitUntilEntered()
        await fixture.selectOtherServer()
        await gate.release()
        await preparation.value

        #expect(session.player == nil)
        #expect(session.errorMessage == nil)
        #expect(!fixture.requests.withLock { $0.contains { $0.url?.path == "/provider/timeline" } })
    }

    @Test
    func seriesBrowserPreservesSeasonOrderAndRequestsTheChosenSeason() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }

        let seasons = await fixture.store.seriesSeasons(ratingKey: "7")
        #expect(seasons.map(\.ratingKey) == ["72", "70"])
        let episodes = await fixture.store.seasonEpisodes(ratingKey: "72")

        #expect(episodes.map(\.ratingKey) == ["42"])
        #expect(fixture.store.errorMessage == nil)
        #expect(!fixture.requests.withLock { $0.contains { $0.url?.path == "/library/metadata/70/children" } })
    }

    @Test
    func failedSeasonRequestSurfacesTheFailureWithoutLoadingAnotherSeason() async throws {
        let fixture = try await Fixture(selectedSeasonStatus: 500)
        defer { fixture.close() }

        let episodes = await fixture.store.seasonEpisodes(ratingKey: "72")

        #expect(episodes.isEmpty)
        #expect(fixture.store.errorMessage?.contains("500") == true)
        #expect(!fixture.requests.withLock { $0.contains { $0.url?.path == "/library/metadata/70/children" } })
    }

    @Test
    func closingBeforeTheInitialSeekPreservesTheResumePositionInPlex() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        let request = TVPlexPlaybackRequest(item: try Self.item(Self.episodeJSON), startTime: 123)
        let session = fixture.makePlaybackSession()
        var timelineRequests = fixture.timelineRequests.makeAsyncIterator()
        var homeRequests = fixture.homeRequests.makeAsyncIterator()
        _ = await homeRequests.next()

        await session.prepare(request: request, store: fixture.store)
        #expect(session.player != nil)
        session.stop(request: request)

        let report = try #require(await timelineRequests.next())
        let query = URLComponents(url: report.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "state", value: "stopped")))
        #expect(query.contains(URLQueryItem(name: "time", value: "123000")))
        _ = await homeRequests.next()
        await fixture.waitForRefreshCompletion()
    }

    @Test
    func failureBeforeTheInitialSeekRetriesFromTheSavedPosition() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        let request = TVPlexPlaybackRequest(item: try Self.item(Self.episodeJSON), startTime: 123)
        let session = fixture.makePlaybackSession()
        var timelineRequests = fixture.timelineRequests.makeAsyncIterator()
        var homeRequests = fixture.homeRequests.makeAsyncIterator()
        _ = await homeRequests.next()

        await session.prepare(request: request, store: fixture.store)
        let playerItem = try #require(session.player?.currentItem)
        await withCheckedContinuation { continuation in
            withObservationTracking {
                _ = session.errorMessage
            } onChange: {
                continuation.resume()
            }
            NotificationCenter.default.post(
                name: AVPlayerItem.failedToPlayToEndTimeNotification,
                object: playerItem
            )
        }
        #expect(session.canRetryPlayback)
        _ = try #require(await timelineRequests.next())

        await session.retry(request: request, store: fixture.store)
        let decisionRequests = fixture.requests.withLock {
            $0.filter { $0.url?.path == "/video/:/transcode/universal/decision" }
        }
        #expect(decisionRequests.count == 2)
        let retryRequest = try #require(decisionRequests.last)
        let query = URLComponents(url: retryRequest.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "offset", value: "123")))
        session.stop(request: request)
        _ = try #require(await timelineRequests.next())
        _ = await homeRequests.next()
        await fixture.waitForRefreshCompletion()
    }

    private func prepare(_ item: PlexMediaItem, in store: TVAppStore, resume: Bool = true) async {
        store.play(item, resume: resume)
        await withCheckedContinuation { continuation in
            withObservationTracking {
                _ = store.playbackRequest
                _ = store.errorMessage
            } onChange: {
                continuation.resume()
            }
        }
    }

    @Test
    func libraryUsesServerSortsFiltersAndPreservesOptionsOnPagination() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        let library = try JSONDecoder().decode(TVPlexLibrary.self, from: Data(#"{"key":"1","title":"Movies","type":"movie"}"#.utf8))
        let definition = try await fixture.store.libraryBrowseDefinition(library)
        #expect(definition.sorts.map(\.title) == ["Title"])
        #expect(definition.booleanFilters.map(\.id) == ["unwatched"])
        let genre = try #require(definition.valueFilters.first)
        let values = try await fixture.store.libraryFilterValues(genre)
        #expect(values.map(\.title) == ["Comedy", "Drama"])
        let options = PlexLibraryBrowseOptions(
            sort: definition.sorts.first?.selection(direction: .descending),
            enabledBooleanFilterIDs: ["unwatched"], valueFilterSelections: values
        )
        await fixture.store.loadLibrary(library, options: options)
        let first = try #require(fixture.store.libraryItems[library.id]?.last)
        await fixture.store.loadMoreLibraryItems(library, currentItem: first)
        let second = try #require(fixture.store.libraryItems[library.id]?.last)
        await fixture.store.loadMoreLibraryItems(library, currentItem: second)
        let requests = fixture.requests.withLock { $0.filter { $0.url?.path == "/library/sections/1/all" } }
        #expect(requests.map { $0.value(forHTTPHeaderField: "X-Plex-Container-Start") } == ["0", "1", "2"])
        for request in requests {
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(query.contains(URLQueryItem(name: "sort", value: "titleSort:desc")))
            #expect(query.contains(URLQueryItem(name: "unwatched", value: "1")))
            #expect(query.contains(URLQueryItem(name: "genre", value: "10,20")))
        }
        #expect(fixture.store.libraryItems[library.id]?.map(\.ratingKey) == ["sorted", "last"])
    }

    @Test
    func staleLibraryQueryCannotReplaceNewSortResults() async throws {
        let gate = TVTimelineResponseGate()
        let fixture = try await Fixture(libraryGate: gate)
        defer { fixture.close() }
        let library = try JSONDecoder().decode(TVPlexLibrary.self, from: Data(#"{"key":"1","title":"Movies","type":"movie"}"#.utf8))
        let first = Task { await fixture.store.loadLibrary(library) }
        await gate.waitUntilEntered()
        let options = PlexLibraryBrowseOptions(sort: PlexLibrarySortSelection(sortID: "titleSort", direction: .ascending, queryValue: "titleSort"))
        await fixture.store.loadLibrary(library, options: options)
        #expect(fixture.store.libraryItems[library.id]?.first?.ratingKey == "sorted")
        await gate.release()
        await first.value
        #expect(fixture.store.libraryItems[library.id]?.first?.ratingKey == "sorted")
        #expect(!fixture.store.isLoading(library))
    }

    @Test(arguments: [200, 500])
    func serverSwitchClearsLibrariesBeforeRefreshCompletes(status: Int) async throws {
        let gate = TVTimelineResponseGate()
        let fixture = try await Fixture(includeLibraries: true, otherServerLibrariesGate: gate, otherServerLibrariesStatus: status)
        defer { fixture.close() }
        let library = try #require(fixture.store.libraries.first)
        await fixture.store.loadLibrary(library)
        #expect(fixture.store.libraryItems[library.id]?.isEmpty == false)
        let switching = Task { await fixture.selectOtherServer() }
        await gate.waitUntilEntered()
        #expect(fixture.store.libraries.isEmpty)
        #expect(fixture.store.libraryItems.isEmpty)
        #expect(fixture.store.libraryTotalSizes.isEmpty)
        #expect(fixture.store.libraryErrors.isEmpty)
        #expect(!fixture.store.isLoading(library))
        await gate.release()
        await switching.value
        if status == 500 {
            #expect(fixture.store.libraries.isEmpty)
            #expect(fixture.store.errorMessage?.contains("500") == true)
        } else {
            let other = try #require(fixture.store.libraries.first)
            #expect(other.id == library.id)
            #expect(other.title == "Other Movies")
            await fixture.store.loadLibrary(other)
            #expect(fixture.store.libraryItems[other.id]?.map(\.ratingKey) == ["other"])
        }
    }

    @Test func oldLibraryRequestCannotRestoreDataAfterServerSwitch() async throws {
        let gate = TVTimelineResponseGate()
        let fixture = try await Fixture(libraryGate: gate, includeLibraries: true)
        defer { fixture.close() }
        let library = try #require(fixture.store.libraries.first)
        let oldLoad = Task { await fixture.store.loadLibrary(library) }
        await gate.waitUntilEntered()
        await fixture.selectOtherServer()
        #expect(fixture.store.libraryItems.isEmpty)
        let other = try #require(fixture.store.libraries.first)
        await fixture.store.loadLibrary(other)
        await gate.release()
        await oldLoad.value
        #expect(fixture.store.libraryItems[other.id]?.map(\.ratingKey) == ["other"])
        #expect(!fixture.store.isLoading(other))
    }

    @Test
    func failedLibraryLoadHasLocalErrorAndCanRetry() async throws {
        let fixture = try await Fixture(libraryStatus: 500)
        defer { fixture.close() }
        let library = try JSONDecoder().decode(TVPlexLibrary.self, from: Data(#"{"key":"1","title":"Movies","type":"movie"}"#.utf8))
        await fixture.store.loadLibrary(library)
        #expect(fixture.store.libraryItems[library.id] == nil)
        #expect(fixture.store.libraryErrors[library.id]?.contains("500") == true)
        #expect(fixture.store.errorMessage == nil)
        await fixture.store.retryLibrary(library, options: .default)
        #expect(fixture.requests.withLock { $0.filter { $0.url?.path == "/library/sections/1/all" }.count } == 2)
    }

    @Test(arguments: [true, false], ["version", "quality"])
    func changingPlaybackWhileResumeIsLoadingPreservesPositionAndIntent(autoplay: Bool, change: String) async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        let item = try Self.item(#"{"ratingKey":"42","title":"Two versions","type":"episode","duration":1800000,"Media":[{"id":1,"Part":[{"id":2,"key":"/library/parts/2/file.mp4"}]},{"id":3,"Part":[{"id":4,"key":"/library/parts/4/file.mp4"}]}]}"#)
        let request = TVPlexPlaybackRequest(
            item: item, startTime: 123, autoplay: autoplay, playbackRate: .oneAndAHalf
        )
        let session = fixture.makePlaybackSession()
        await session.prepare(request: request, store: fixture.store)
        defer { session.stop(request: request) }
        #expect(session.isPreparingInitialPosition)
        #expect(session.player?.currentTime().seconds == 0)
        #expect(session.playbackVersionSelection?.canSelect(1) == true)

        await withCheckedContinuation { continuation in
            withObservationTracking {
                _ = fixture.store.playbackRequest
            } onChange: {
                continuation.resume()
            }
            if change == "version" {
                session.selectPlaybackVersion(1)
            } else {
                session.selectVideoQuality(.hd4Mbps)
            }
        }

        let replacement = try #require(fixture.store.playbackRequest)
        #expect(replacement.startTime == 123)
        #expect(replacement.autoplay == autoplay)
        #expect(replacement.playbackRate == .oneAndAHalf)
        #expect(replacement.item.ratingKey == item.ratingKey)
        if change == "version" {
            #expect(replacement.source?.mediaIndex == 1)
        } else {
            #expect(replacement.videoQualityOverride == .hd4Mbps)
        }
        let stopped = try #require(fixture.requests.withLock { $0.last { $0.url?.path == "/provider/timeline" } })
        let query = URLComponents(url: stopped.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "time", value: "123000")))
    }

    @Test(arguments: ["next", "prepared-next", "previous", "up-next"], [false, true])
    func explicitQueueNavigationStartsPlaybackAndKeepsSelectedQuality(destination: String, forceConversion: Bool) async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        let item = try Self.item(Self.episodeJSON)
        let request = TVPlexPlaybackRequest(
            item: item, queue: try Self.navigationQueue(), startTime: 123,
            autoplay: false, playbackRate: .oneAndAHalf, videoQualityOverride: .hd4Mbps, forceVideoTranscode: forceConversion
        )
        let session = fixture.makePlaybackSession()
        await session.prepare(request: request, store: fixture.store)
        defer { session.stop(request: request) }
        // Repeat One disables speculative next-item preparation. Explicit navigation
        // must still behave exactly like an already prepared next item.
        if destination == "prepared-next" {
            try await waitFor { session.nextItemTitle == "Selected episode" }
        } else {
            session.setRepeatMode(.one)
        }
        #expect(session.isPreparingInitialPosition)
        #expect(session.canGoNext && session.canGoPrevious)

        switch destination {
        case "next", "prepared-next": session.playNextItem()
        case "previous": session.playPreviousItem()
        default: session.playQueuedItem(playQueueItemID: "503")
        }
        try await waitFor { fixture.store.playbackRequest != nil }
        let replacement = try #require(fixture.store.playbackRequest)
        #expect(replacement.item.ratingKey == (destination == "previous" ? "41" : "43"))
        #expect(replacement.startTime == (destination == "previous" ? 0 : 123))
        #expect(replacement.autoplay, "Choosing a queue item is an explicit Play action, as on macOS.")
        #expect(replacement.playbackRate == .oneAndAHalf)
        #expect(replacement.videoQualityOverride == .hd4Mbps)
        #expect(replacement.forceVideoTranscode == forceConversion)
        #expect(replacement.queue?.currentItem.ratingKey == replacement.item.ratingKey)
        let stopped = try #require(fixture.requests.withLock { $0.last { $0.url?.path == "/provider/timeline" } })
        let query = URLComponents(url: stopped.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "time", value: "123000")))
    }

    @Test(arguments: ["continuous", "repeat", "next-episode"], [false, true])
    func automaticQueueTransitionsKeepSelectedQuality(transition: String, forceConversion: Bool) async throws {
        let fixture = try await Fixture(includeNextEpisode: transition == "next-episode")
        defer { fixture.close() }
        let request = TVPlexPlaybackRequest(
            item: try Self.item(Self.episodeJSON.replacingOccurrences(of: "\"type\":\"episode\"", with: "\"type\":\"episode\",\"parentRatingKey\":\"72\",\"index\":1")),
            queue: transition == "next-episode" ? nil : try Self.navigationQueue(),
            startTime: 123, videoQualityOverride: .hd4Mbps, forceVideoTranscode: forceConversion
        )
        let next: TVPlexPlaybackRequest
        if transition == "repeat" {
            next = try await fixture.store.preparedRepeatedQueue(from: request, playbackRate: .oneAndAHalf)
        } else {
            next = try #require(await fixture.store.preparedNextPlayback(after: request, playbackRate: .oneAndAHalf))
        }
        #expect(next.item.ratingKey == (transition == "repeat" ? "41" : "43"))
        #expect(next.startTime == (transition == "repeat" ? 0 : 123))
        #expect(next.autoplay)
        #expect(next.playbackRate == .oneAndAHalf)
        #expect(next.videoQualityOverride == .hd4Mbps)
        #expect(next.forceVideoTranscode == forceConversion)
    }

    @Test(arguments: [true, false])
    func failedQueueChangePreservesPendingResumeAndCanRetry(autoplay: Bool) async throws {
        let status = OSAllocatedUnfairLock(initialState: 500)
        let fixture = try await Fixture(neighborMetadataStatus: status)
        defer { fixture.close() }
        let request = TVPlexPlaybackRequest(
            item: try Self.item(Self.episodeJSON), queue: try Self.navigationQueue(),
            startTime: 123, autoplay: autoplay, videoQualityOverride: .hd4Mbps
        )
        let session = fixture.makePlaybackSession()
        await session.prepare(request: request, store: fixture.store)
        session.setRepeatMode(.one)
        defer { session.stop(request: request) }
        let originalPlayer = try #require(session.player)
        session.playNextItem()
        try await waitFor { session.queueNavigationErrorMessage != nil }
        #expect(session.queueNavigationErrorMessage?.contains("500") == true)
        #expect(!session.isNavigatingQueue)
        #expect(session.player === originalPlayer)
        #expect(session.isPreparingInitialPosition)
        #expect(originalPlayer.timeControlStatus == .paused, "A failed queue change must not bypass the pending resume seek.")
        #expect(fixture.store.playbackRequest == nil)
        #expect(!fixture.requests.withLock { $0.contains { $0.url?.path == "/provider/timeline" } })

        status.withLock { $0 = 200 }
        session.retryQueueOperation()
        try await waitFor { fixture.store.playbackRequest != nil }
        let retried = try #require(fixture.store.playbackRequest)
        #expect(retried.item.ratingKey == "43")
        #expect(retried.autoplay)
        #expect(retried.videoQualityOverride == .hd4Mbps)
        #expect(session.queueNavigationErrorMessage == nil)
    }

    @Test(arguments: [true, false])
    func failedSubtitleAdjustmentPreservesPendingResumeAndCanBeRetried(autoplay: Bool) async throws {
        let status = OSAllocatedUnfairLock(initialState: 500)
        let metadata = Self.episodeJSON.replacingOccurrences(
            of: "\"key\":\"/library/parts/2/file.mp4\"",
            with: #""key":"/library/parts/2/file.mp4","Stream":[{"id":9,"streamType":3,"codec":"srt","location":"external","selected":true,"offset":0}]"#
        )
        let fixture = try await Fixture(episodeMetadata: metadata, subtitleOffsetStatus: status)
        defer { fixture.close() }
        let request = TVPlexPlaybackRequest(
            item: try Self.item(metadata), startTime: 123, autoplay: autoplay,
            playbackRate: .oneAndAHalf, videoQualityOverride: .hd4Mbps
        )
        let session = fixture.makePlaybackSession()
        await session.prepare(request: request, store: fixture.store)
        defer { session.stop(request: request) }
        let player = try #require(session.player)
        #expect(session.subtitleOffsetSelection?.streamID == 9)
        session.setSubtitleOffset(100)
        try await waitFor { session.mediaSelectionErrorMessage != nil }
        #expect(session.mediaSelectionErrorMessage?.contains("500") == true)
        #expect(session.isPreparingInitialPosition)
        #expect(session.player === player)
        #expect(player.timeControlStatus == .paused, "A subtitle request failure must not start video before the saved-position seek.")
        #expect(fixture.store.playbackRequest == nil)

        status.withLock { $0 = 200 }
        session.setSubtitleOffset(100)
        try await waitFor { fixture.store.playbackRequest != nil }
        let replacement = try #require(fixture.store.playbackRequest)
        #expect(replacement.startTime == 123)
        #expect(replacement.autoplay == autoplay)
        #expect(replacement.playbackRate == .oneAndAHalf)
        #expect(replacement.videoQualityOverride == .hd4Mbps)
        #expect(session.mediaSelectionErrorMessage == nil)
        let update = try #require(fixture.requests.withLock { $0.last { $0.url?.path == "/library/streams/9" } })
        #expect(update.httpMethod == "PUT")
        #expect(URLComponents(url: update.url!, resolvingAgainstBaseURL: false)?.queryItems?
            .contains(URLQueryItem(name: "offset", value: "100")) == true)
    }

    @Test
    func failedEndTransitionIgnoresDuplicateEventsUntilExplicitRetry() async throws {
        let status = OSAllocatedUnfairLock(initialState: 500)
        let fixture = try await Fixture(neighborMetadataStatus: status)
        defer { fixture.close() }
        fixture.store.autoplayNextEpisode = true
        fixture.store.autoplayCountdown = .immediate
        let request = TVPlexPlaybackRequest(
            item: try Self.item(Self.episodeJSON), queue: try Self.navigationQueue(),
            startTime: 123, videoQualityOverride: .hd4Mbps
        )
        let session = fixture.makePlaybackSession()
        await session.prepare(request: request, store: fixture.store)
        defer { session.stop(request: request) }
        let playerItem = try #require(session.player?.currentItem)
        // A failed speculative lookup must still allow one authoritative attempt at EOF.
        try await waitFor { fixture.requests.withLock { $0.contains { $0.url?.path == "/library/metadata/43" } } }
        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: playerItem)
        try await waitFor { session.queueNavigationErrorMessage != nil }
        #expect(session.canRetryQueueOperation)
        #expect(session.queueNavigationErrorMessage?.contains("500") == true)
        let failedLookupCount = fixture.requests.withLock { $0.filter { $0.url?.path == "/library/metadata/43" }.count }
        #expect(failedLookupCount == 2)

        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: playerItem)
        // Allow the notification's main-actor task and mock response to settle.
        try await Task.sleep(for: .milliseconds(50))
        #expect(fixture.requests.withLock { $0.filter { $0.url?.path == "/library/metadata/43" }.count } == failedLookupCount,
                "Duplicate end notifications must not silently retry a failed transition.")
        #expect(fixture.store.playbackRequest == nil)
        #expect(session.canRetryQueueOperation)

        status.withLock { $0 = 200 }
        session.retryQueueOperation()
        try await waitFor { fixture.store.playbackRequest != nil }
        let replacement = try #require(fixture.store.playbackRequest)
        #expect(replacement.item.ratingKey == "43")
        #expect(replacement.autoplay)
        #expect(replacement.videoQualityOverride == .hd4Mbps)
    }

    @Test(arguments: ["accept", "reject"])
    func nativeContentProposalRemainsActionableAfterEnd(action: String) async throws {
        let gate = TVTimelineResponseGate()
        let fixture = try await Fixture(watchedStateGate: gate)
        defer { fixture.close() }
        fixture.store.autoplayNextEpisode = true
        fixture.store.autoplayCountdown = .fiveSeconds
        let request = TVPlexPlaybackRequest(
            item: try Self.item(Self.episodeJSON), queue: try Self.navigationQueue(),
            startTime: 123, playbackRate: .oneAndAHalf, videoQualityOverride: .hd4Mbps
        )
        fixture.store.presentPlayback(request)
        let session = fixture.makePlaybackSession()
        await session.prepare(request: request, store: fixture.store)
        defer { session.stop(request: request) }
        let playerItem = try #require(session.player?.currentItem)
        try await waitFor { playerItem.nextContentProposal != nil }
        let proposal = try #require(playerItem.nextContentProposal)
        #expect(proposal.automaticAcceptanceInterval == 5)
        #expect(session.shouldPresentContentProposal(proposal))
        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: playerItem)
        try await Task.sleep(for: .milliseconds(30))
        #expect(fixture.store.playbackRequest?.id == request.id,
                "AVKit owns the visible proposal until the user accepts or rejects it.")
        #expect(session.shouldPresentContentProposal(proposal))
        await gate.waitUntilEntered()

        if action == "accept" {
            session.acceptContentProposal(proposal)
            try await waitFor { fixture.store.playbackRequest?.id != request.id }
            let replacement = try #require(fixture.store.playbackRequest)
            #expect(replacement.item.ratingKey == "43")
            #expect(replacement.playbackRate == .oneAndAHalf)
            #expect(replacement.videoQualityOverride == .hd4Mbps)
            session.acceptContentProposal(proposal)
            #expect(fixture.store.playbackRequest?.id == replacement.id)
        } else {
            session.rejectContentProposal(proposal)
            try await waitFor { fixture.store.playbackRequest == nil }
            session.acceptContentProposal(proposal)
            #expect(fixture.store.playbackRequest == nil,
                    "A stale acceptance must not reopen playback after rejection.")
        }
        #expect(!session.shouldPresentContentProposal(proposal))
        #expect(playerItem.nextContentProposal == nil)
        #expect(fixture.watchedStateRequests.count == 1,
                "The end notification and proposal acceptance must share one watched-state update.")
        await gate.release()
        // Reject also refreshes after its final timeline report; drain both writes
        // before invalidating the fixture's network session.
        let expectedHomeRequests = action == "accept" ? 2 : 3
        try await waitFor {
            fixture.homeRequestCount == expectedHomeRequests
                && !fixture.store.isLoadingHome && !fixture.store.isLoadingLibraries
        }
    }

    @Test
    func hubBrowsePreservesQueryAndPagesByRawRows() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        let browser = TVHubBrowseStore()
        let hub = try Self.browseHub()
        await browser.load(hub: hub, using: fixture.store)
        #expect(browser.items.map(\.ratingKey) == ["a", "b"])
        #expect(browser.hasMore)
        await browser.loadMore(hub: hub, using: fixture.store)
        #expect(browser.items.map(\.ratingKey) == ["a", "b", "c"])
        #expect(browser.hasMore)
        await browser.loadMore(hub: hub, using: fixture.store)
        #expect(browser.items.map(\.ratingKey) == ["a", "b", "c", "d"])
        #expect(!browser.hasMore)
        let requests = fixture.requests.withLock { $0.filter { $0.url?.path == "/hubs/all" } }
        #expect(requests.map { $0.value(forHTTPHeaderField: "X-Plex-Container-Start") } == ["0", "2", "4"])
        for request in requests {
            #expect(request.value(forHTTPHeaderField: "X-Plex-Container-Size") == "60")
            #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?
                .contains(URLQueryItem(name: "query", value: "star wars")) == true)
        }
    }

    @Test(arguments: [0, 2])
    func hubBrowseRetriesOnlyTheFailedPage(offset: Int) async throws {
        let status = OSAllocatedUnfairLock(initialState: 500)
        let fixture = try await Fixture(hubStatus: status, failingHubOffset: offset)
        defer { fixture.close() }
        let browser = TVHubBrowseStore()
        let hub = try Self.browseHub()
        await browser.load(hub: hub, using: fixture.store)
        if offset > 0 { await browser.loadMore(hub: hub, using: fixture.store) }
        #expect(browser.errorMessage?.contains("500") == true)
        #expect(browser.items.count == offset)
        #expect(!browser.isLoading)
        #expect(fixture.store.errorMessage == nil)
        status.withLock { $0 = 200 }
        await browser.retry(hub: hub, using: fixture.store)
        #expect(browser.errorMessage == nil)
        #expect(browser.items.map(\.ratingKey) == (offset == 0 ? ["a", "b"] : ["a", "b", "c"]))
        let attempts = fixture.requests.withLock { $0.filter { $0.url?.path == "/hubs/all" } }
        #expect(attempts.suffix(2).map { $0.value(forHTTPHeaderField: "X-Plex-Container-Start") } == [String(offset), String(offset)])
    }

    @Test
    func oldHubResponseCannotOverwriteNewHub() async throws {
        let gate = TVTimelineResponseGate()
        let fixture = try await Fixture(hubGate: gate)
        defer { fixture.close() }
        let browser = TVHubBrowseStore()
        let oldHub = try Self.browseHub()
        let newHub = try Self.browseHub(path: "/hubs/other")
        let oldLoad = Task { await browser.load(hub: oldHub, using: fixture.store) }
        await gate.waitUntilEntered()
        await browser.load(hub: newHub, using: fixture.store)
        #expect(browser.items.map(\.ratingKey) == ["new"])
        await gate.release()
        await oldLoad.value
        #expect(browser.items.map(\.ratingKey) == ["new"])
        #expect(!browser.isLoading)
        #expect(browser.errorMessage == nil)
    }

    @Test
    func homePaginationExcludesAudioAndAdvancesByUnfilteredOffsets() async throws {
        let fixture = try await Fixture(hubIncludesAudio: true)
        defer { fixture.close() }
        let browser = TVHubBrowseStore(videoOnly: true)
        let hub = try Self.browseHub()
        await browser.load(hub: hub, using: fixture.store)
        #expect(browser.items.map(\.ratingKey) == ["a"])
        let first = try #require(browser.items.first)
        await browser.loadInline(hub: hub, using: fixture.store, after: first)
        #expect(browser.items.map(\.ratingKey) == ["a", "c", "d"])
        #expect(!browser.hasMore)
        let offsets = fixture.requests.withLock { $0.filter { $0.url?.path == "/hubs/all" }
            .map { $0.value(forHTTPHeaderField: "X-Plex-Container-Start") } }
        #expect(offsets == ["0", "2", "4"])
    }

    @Test
    func inlineHubKeepsPreviewAndLoadsPastOverlappingPages() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        let browser = TVHubBrowseStore()
        var hub = try Self.browseHub()
        await browser.load(hub: hub, using: fixture.store)
        hub.metadata = browser.items
        let inline = TVHubBrowseStore()
        #expect(inline.visibleItems(hub: hub, connection: fixture.store.connection).map(\.ratingKey) == ["a", "b"])
        await inline.loadInline(hub: hub, using: fixture.store, after: hub.metadata[1])
        #expect(inline.items.map(\.ratingKey) == ["a", "b", "c", "d"])
        #expect(!inline.hasMore)
        #expect(inline.errorMessage == nil)
    }

    @Test
    func inlineHubFailurePreservesCardsAndRequiresExplicitRetry() async throws {
        let status = OSAllocatedUnfairLock(initialState: 200)
        let fixture = try await Fixture(hubStatus: status)
        defer { fixture.close() }
        let preview = TVHubBrowseStore()
        var hub = try Self.browseHub()
        await preview.load(hub: hub, using: fixture.store)
        hub.metadata = preview.items
        status.withLock { $0 = 500 }
        let inline = TVHubBrowseStore()
        await inline.loadInline(hub: hub, using: fixture.store, after: hub.metadata[1])
        #expect(inline.items == hub.metadata)
        #expect(inline.errorMessage?.contains("500") == true)
        let requestCount = fixture.requests.withLock { $0.count }
        await inline.loadInline(hub: hub, using: fixture.store, after: hub.metadata[1])
        #expect(fixture.requests.withLock { $0.count } == requestCount)
        status.withLock { $0 = 200 }
        await inline.retry(hub: hub, using: fixture.store)
        #expect(inline.errorMessage == nil)
        #expect(inline.items == hub.metadata)
    }

    private static func browseHub(path: String = "/hubs/all?query=star%20wars&type=1") throws -> PlexHub {
        try JSONDecoder().decode(PlexHub.self, from: JSONSerialization.data(withJSONObject: [
            "hubIdentifier": path, "title": "Movies", "key": path, "more": true, "totalSize": 5,
            "Metadata": []
        ]))
    }

    @Test
    func searchUsesAdvertisedEndpointAndKeepsFailureLocal() async throws {
        let status = OSAllocatedUnfairLock(initialState: 500)
        let fixture = try await Fixture(searchStatus: status)
        defer { fixture.close() }
        fixture.store.searchQuery = "star wars"
        fixture.store.submitSearch()
        try await waitFor { !fixture.store.isSearching }
        #expect(fixture.store.searchErrorMessage?.contains("500") == true)
        #expect(fixture.store.errorMessage == nil)
        #expect(fixture.store.searchHubs.isEmpty)
        status.withLock { $0 = 200 }
        fixture.store.submitSearch()
        try await waitFor { !fixture.store.isSearching }
        #expect(fixture.store.searchErrorMessage == nil)
        #expect(fixture.store.searchHubs.first?.key == "/hubs/all?query=star%20wars&type=1")
        #expect(fixture.requests.withLock { $0.filter { $0.url?.path == "/provider/search" }.count } == 2)
        fixture.store.searchQuery = ""
        fixture.store.submitSearch()
        #expect(fixture.store.searchHubs.isEmpty)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Playback operation did not complete within five seconds.")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func navigationQueue() throws -> PlexPlaybackQueue {
        try PlexPlaybackQueue(page: JSONDecoder().decode(
            PlexPlayQueueEnvelope.self, from: Data(navigationQueueJSON.utf8)
        ).mediaContainer.page(), selectedRatingKey: "42")
    }

    private static let navigationQueueJSON = #"{"MediaContainer":{"playQueueID":9,"playQueueVersion":1,"playQueueTotalCount":3,"playQueueSelectedItemID":502,"playQueueSelectedItemOffset":1,"offset":0,"Metadata":[{"ratingKey":"41","title":"Previous episode","type":"episode","playQueueItemID":"501"},{"ratingKey":"42","title":"Current episode","type":"episode","playQueueItemID":"502"},{"ratingKey":"43","title":"Next episode","type":"episode","playQueueItemID":"503"}]}}"#

    private static func item(_ json: String) throws -> PlexMediaItem {
        try JSONDecoder().decode(PlexMediaItem.self, from: Data(json.utf8))
    }

    private static func hierarchyJSON(type: String) -> String {
        #"{"ratingKey":"7","key":"/library/metadata/7/children","title":"Series","type":"\#(type)","Media":[]}"#
    }

    private static let episodeJSON = #"{"ratingKey":"42","key":"/library/metadata/42","title":"Selected episode","type":"episode","viewOffset":123000,"duration":1800000,"Media":[{"id":1,"Part":[{"id":2,"key":"/library/parts/2/file.mp4"}]}]}"#

    private final class TVPendingAssetLoader: NSObject, AVAssetResourceLoaderDelegate {
        nonisolated func resourceLoader(
            _ resourceLoader: AVAssetResourceLoader,
            shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
        ) -> Bool {
            true
        }
    }

    @MainActor
    private final class Fixture {
        let store: TVAppStore
        let requests = OSAllocatedUnfairLock(initialState: [URLRequest]())
        let homeRequests: AsyncStream<Void>
        let timelineRequests: AsyncStream<URLRequest>
        private let pendingAssetLoader = TVPendingAssetLoader()
        private let session: URLSession
        private let defaults: UserDefaults
        private let defaultsName = "TVPlaybackPreparationTests.\(UUID())"
        private let topShelfPublisher: TVTopShelfPublisher

        init(
            hierarchyType: String = "show",
            selectedEpisodeStatus: Int = 200,
            selectedSeasonStatus: Int = 200,
            timelineGate: TVTimelineResponseGate? = nil,
            watchedStateGate: TVTimelineResponseGate? = nil,
            watchedStateStatus: OSAllocatedUnfairLock<Int>? = nil,
            providerStatus: OSAllocatedUnfairLock<Int>? = nil,
            includesScrobbleEndpoint: Bool = true,
            homeStatus: OSAllocatedUnfairLock<Int>? = nil,
            playbackPlanGate: TVTimelineResponseGate? = nil,
            libraryGate: TVTimelineResponseGate? = nil,
            libraryStatus: Int = 200,
            includeLibraries: Bool = false,
            otherServerLibrariesGate: TVTimelineResponseGate? = nil,
            otherServerLibrariesStatus: Int = 200,
            neighborMetadataStatus: OSAllocatedUnfairLock<Int>? = nil,
            episodeMetadata: String? = nil,
            includeNextEpisode: Bool = false,
            subtitleOffsetStatus: OSAllocatedUnfairLock<Int>? = nil,
            hubStatus: OSAllocatedUnfairLock<Int>? = nil,
            failingHubOffset: Int = 0,
            hubGate: TVTimelineResponseGate? = nil,
            searchStatus: OSAllocatedUnfairLock<Int>? = nil,
            hubIncludesAudio: Bool = false
        ) async throws {
            let homeEvents = AsyncStream<Void>.makeStream()
            let timelineEvents = AsyncStream<URLRequest>.makeStream()
            homeRequests = homeEvents.stream
            timelineRequests = timelineEvents.stream
            defaults = try #require(UserDefaults(suiteName: defaultsName))
            let requests = requests
            let hierarchy = TVPlaybackPreparationTests.hierarchyJSON(type: hierarchyType)
            let episode = episodeMetadata ?? TVPlaybackPreparationTests.episodeJSON
            let navigationQueue = TVPlaybackPreparationTests.navigationQueueJSON
            TVPlaybackMockProtocol.handler.withLock { handler in
                handler = { request in
                    requests.withLock { $0.append(request) }
                    let json: String
                    switch request.url?.path {
                    case "/identity":
                        let serverID = request.url?.host == "other.plex.test" ? "other-server" : "test-server"
                        json = #"{"MediaContainer":{"machineIdentifier":"\#(serverID)","friendlyName":"Test Server"}}"#
                    case "/hubs/promoted":
                        homeEvents.continuation.yield(())
                        json = #"{"MediaContainer":{"Hub":[]}}"#
                    case "/hubs/continueWatching":
                        json = #"{"MediaContainer":{"Hub":[]}}"#
                    case "/library/sections/all":
                        if request.url?.host == "other.plex.test", let otherServerLibrariesGate {
                            await otherServerLibrariesGate.blockResponse()
                        }
                        let title = request.url?.host == "other.plex.test" ? "Other Movies" : "Movies"
                        json = includeLibraries
                            ? #"{"MediaContainer":{"Directory":[{"key":"1","title":"\#(title)","type":"movie","composite":"/library/sections/1/composite"}]}}"#
                            : #"{"MediaContainer":{"Directory":[]}}"#
                    case "/library/sections/1/filters":
                        json = #"{"MediaContainer":{"Directory":[{"filter":"genre","title":"Genre","filterType":"string","key":"/library/sections/1/genre"},{"filter":"unwatched","title":"Unplayed","filterType":"boolean"}]}}"#
                    case "/library/sections/1/sorts":
                        json = #"{"MediaContainer":{"Directory":[{"key":"titleSort","title":"Title","descKey":"titleSort:desc"}]}}"#
                    case "/library/sections/1/genre":
                        json = #"{"MediaContainer":{"Directory":[{"key":"10","title":"Comedy"},{"key":"20","title":"Drama"}]}}"#
                    case "/provider/search":
                        json = #"{"MediaContainer":{"Hub":[{"hubIdentifier":"search.movies","title":"Movies","key":"/hubs/all?query=star%20wars&type=1","more":true,"totalSize":5,"Metadata":[{"ratingKey":"a","title":"Star Wars","type":"movie"}]}]}}"#
                    case "/hubs/all", "/hubs/other":
                        let offset = Int(request.value(forHTTPHeaderField: "X-Plex-Container-Start") ?? "0") ?? 0
                        if request.url?.path == "/hubs/all", offset == 0, let hubGate { await hubGate.blockResponse() }
                        let keys = request.url?.path == "/hubs/other" ? ["new"] : offset == 0 ? ["a", "b"] : offset == 2 ? ["b", "c"] : ["d"]
                        let payload: [String: Any] = ["MediaContainer": ["offset": offset, "totalSize": request.url?.path == "/hubs/other" ? 1 : 5,
                            "Metadata": keys.map { ["ratingKey": $0, "title": $0, "type": hubIncludesAudio && $0 == "b" ? "album" : "movie"] }]]
                        json = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
                    case "/library/sections/1/all":
                        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
                        let sorted = query.contains { $0.name == "sort" }
                        if !sorted, request.url?.host == "plex.test", let libraryGate { await libraryGate.blockResponse() }
                        let offset = Int(request.value(forHTTPHeaderField: "X-Plex-Container-Start") ?? "0") ?? 0
                        let key = request.url?.host == "other.plex.test" ? "other" : offset == 2 ? "last" : sorted ? "sorted" : "default"
                        json = #"{"MediaContainer":{"offset":\#(offset),"totalSize":3,"Metadata":[{"ratingKey":"\#(key)","title":"Item","type":"movie"}]}}"#
                    case "/library/metadata/7":
                        json = #"{"MediaContainer":{"Metadata":[\#(hierarchy)]}}"#
                    case "/library/metadata/41", "/library/metadata/43":
                        let key = request.url!.lastPathComponent
                        json = #"{"MediaContainer":{"Metadata":[\#(episode.replacingOccurrences(of: "42", with: key))]}}"#
                    case "/library/streams/9":
                        json = #"{"MediaContainer":{}}"#
                    case "/provider/queue/9/reset":
                        json = navigationQueue
                            .replacingOccurrences(of: "\"playQueueSelectedItemID\":502", with: "\"playQueueSelectedItemID\":501")
                            .replacingOccurrences(of: "\"playQueueSelectedItemOffset\":1", with: "\"playQueueSelectedItemOffset\":0")
                    case "/library/metadata/42":
                        json = #"{"MediaContainer":{"Metadata":[\#(episode)]}}"#
                    case "/library/metadata/7/children":
                        json = #"{"MediaContainer":{"Metadata":[{"ratingKey":"72","type":"season","title":"Season 2","index":2},{"ratingKey":"70","type":"season","title":"Season 1","index":1}]}}"#
                    case "/library/metadata/72/children":
                        let next = episode.replacingOccurrences(of: "42", with: "43")
                            .replacingOccurrences(of: "\"type\":\"episode\"", with: "\"type\":\"episode\",\"index\":2")
                        json = includeNextEpisode
                            ? #"{"MediaContainer":{"Metadata":[\#(episode),\#(next)]}}"#
                            : #"{"MediaContainer":{"Metadata":[\#(episode)]}}"#
                    case "/media/providers":
                        json = #"{"MediaContainer":{"MediaProvider":[{"identifier":"com.plexapp.plugins.library","Feature":[{"type":"promoted","key":"/hubs/promoted"},{"type":"continuewatching","key":"/hubs/continueWatching"},{"type":"search","key":"/provider/search"},{"type":"playqueue","key":"/provider/queue"},{"type":"timeline","key":"/provider/timeline"\#(includesScrobbleEndpoint ? ",\"scrobbleKey\":\"/provider/scrobble\"" : "")}]}]}}"#
                    case "/provider/scrobble":
                        if let watchedStateGate { await watchedStateGate.blockResponse() }
                        json = #"{"MediaContainer":{}}"#
                    case "/provider/timeline":
                        timelineEvents.continuation.yield(request)
                        if request.url?.host == "plex.test", let timelineGate {
                            await timelineGate.blockResponse()
                        }
                        json = #"{"MediaContainer":{}}"#
                    case "/video/:/transcode/universal/decision":
                        if let playbackPlanGate { await playbackPlanGate.blockResponse() }
                        json = #"{"MediaContainer":{"generalDecisionCode":1000,"Metadata":[{"ratingKey":"42","title":"Episode","Media":[{"Part":[{"decision":"directplay","key":"/library/parts/2/file.mp4"}]}]}]}}"#
                    case "/provider/queue":
                        json = #"{"MediaContainer":{"playQueueID":9,"playQueueVersion":1,"playQueueTotalCount":2,"playQueueSelectedItemID":502,"playQueueSelectedItemOffset":1,"offset":0,"Metadata":[{"ratingKey":"41","title":"Earlier episode","type":"episode","playQueueItemID":"501"},{"ratingKey":"42","title":"Selected episode","type":"episode","playQueueItemID":"502"}]}}"#
                    default:
                        throw URLError(.unsupportedURL)
                    }
                    let statusCode = switch request.url?.path {
                    case "/media/providers": providerStatus?.withLock { $0 } ?? 200
                    case "/provider/scrobble": watchedStateStatus?.withLock { $0 } ?? 200
                    case "/hubs/promoted": homeStatus?.withLock { $0 } ?? 200
                    case "/provider/search": searchStatus?.withLock { $0 } ?? 200
                    case "/hubs/all": Int(request.value(forHTTPHeaderField: "X-Plex-Container-Start") ?? "0") == failingHubOffset ? hubStatus?.withLock { $0 } ?? 200 : 200
                    case "/library/streams/9": subtitleOffsetStatus?.withLock { $0 } ?? 200
                    case "/library/metadata/42": selectedEpisodeStatus
                    case "/library/metadata/41", "/library/metadata/43": neighborMetadataStatus?.withLock { $0 } ?? 200
                    case "/library/metadata/72/children": selectedSeasonStatus
                    case "/library/sections/1/all": libraryStatus
                    case "/library/sections/all": request.url?.host == "other.plex.test" ? otherServerLibrariesStatus : 200
                    default: 200
                    }
                    let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                    return (response, Data(json.utf8))
                }
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [TVPlaybackMockProtocol.self]
            session = URLSession(configuration: configuration)
            let topShelfCache = TVTopShelfCache(
                directory: FileManager.default.temporaryDirectory.appending(path: defaultsName)
            )
            topShelfPublisher = TVTopShelfPublisher(cache: { topShelfCache }, notify: {})
            let accountStorage = TVPlexAccountJWTStorage(
                defaults: defaults,
                credentialStore: PlexMemoryCredentialStore(credentials: PlexStoredCredentials(userToken: "test-account", serverToken: ""))
            )
            try await accountStorage.loadAccountToken()
            store = TVAppStore(
                client: TVPlexClient(session: session),
                defaults: defaults,
                keychain: KeychainStore(service: defaultsName),
                topShelfPublisher: topShelfPublisher,
                accountStorage: accountStorage
            )
            let server = PlexServerResource(
                id: "test-server", name: "Test Server", productVersion: nil, accessToken: "test-token",
                connections: [PlexServerConnection(uri: URL(string: "https://plex.test")!, local: true, relay: false)]
            )
            store.availableServers = [server]
            await store.selectServer(server)
            #expect(store.isConnected)
        }

        func makeClient() -> TVPlexClient { TVPlexClient(session: session) }

        var watchedStateRequests: [URLRequest] {
            requests.withLock { $0.filter { $0.url?.path == "/provider/scrobble" } }
        }

        var homeRequestCount: Int {
            requests.withLock { $0.filter { $0.url?.path == "/hubs/promoted" }.count }
        }

        func makePlaybackSession() -> TVPlaybackSession {
            let loader = pendingAssetLoader
            return TVPlaybackSession { _ in
                // Keep native AVPlayer in the loading state deterministically while
                // exercising resume and queue orchestration, without external DNS.
                let asset = AVURLAsset(url: URL(string: "plexbar-test://pending/media.mp4")!)
                asset.resourceLoader.setDelegate(loader, queue: .main)
                return AVPlayerItem(asset: asset)
            }
        }

        func selectOtherServer() async {
            let server = PlexServerResource(
                id: "other-server", name: "Other Server", productVersion: nil, accessToken: "other-token",
                connections: [PlexServerConnection(uri: URL(string: "https://other.plex.test")!, local: true, relay: false)]
            )
            store.availableServers = [server]
            await store.selectServer(server)
            #expect(store.connection?.serverIdentifier == "other-server")
        }

        func close() {
            topShelfPublisher.clear()
            session.invalidateAndCancel()
            defaults.removePersistentDomain(forName: defaultsName)
        }

        func waitForRefreshCompletion() async {
            guard store.isLoadingHome || store.isLoadingLibraries else { return }
            await withCheckedContinuation { continuation in
                withObservationTracking {
                    _ = store.isLoadingHome
                    _ = store.isLoadingLibraries
                } onChange: {
                    continuation.resume()
                }
            }
        }
    }
}

private final class TVPlaybackMockProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) async throws -> (HTTPURLResponse, Data)
    static let handler = Mutex<Handler?>(nil)
    private let loadingTask = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler.withLock({ $0 }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let task = Task { @Sendable [self, request = request] in
            do {
                let (response, data) = try await handler(request)
                guard !Task.isCancelled else { return }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
        loadingTask.withLock { $0 = task }
    }
    override func stopLoading() {
        loadingTask.withLock { $0?.cancel() }
    }
}

private actor TVTimelineResponseGate {
    private var hasEntered = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func blockResponse() async {
        await withCheckedContinuation { continuation in
            releaseWaiter = continuation
            hasEntered = true
            entryWaiter?.resume()
            entryWaiter = nil
        }
    }

    func waitUntilEntered() async {
        guard !hasEntered else { return }
        await withCheckedContinuation { entryWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

#endif
