import PlexModels
import Foundation
import Testing
@testable import PlexBar

@Suite(.serialized)
struct PlexPlayQueueTests {
    @Test func queueMutationRequestsShareValidatedServerPathComponents() throws {
        #expect(try PlexPlayQueueMutationRequest(
            queueID: 91,
            mutation: .shuffled(true)
        ).endpointPathComponents == ["91", "shuffle"])
        #expect(try PlexPlayQueueMutationRequest(
            queueID: 91,
            mutation: .shuffled(false)
        ).endpointPathComponents == ["91", "unshuffle"])
        #expect(try PlexPlayQueueMutationRequest(
            queueID: 91,
            mutation: .reset
        ).endpointPathComponents == ["91", "reset"])
        #expect(throws: PlexAPIError.self) {
            _ = try PlexPlayQueueMutationRequest(
                queueID: 0,
                mutation: .reset
            )
        }
    }

    @Test func queueItemMutationRequestsShareValidatedServerContracts() throws {
        let removal = try PlexPlayQueueItemMutationRequest(
            queueID: 91,
            mutation: .remove(playQueueItemID: "503")
        )
        #expect(removal.endpointPathComponents == ["91", "items", "503"])
        #expect(removal.method == "DELETE")
        #expect(removal.queryItems.isEmpty)

        let move = try PlexPlayQueueItemMutationRequest(
            queueID: 91,
            mutation: .move(PlexPlayQueueItemMove(
                playQueueItemID: "504",
                afterPlayQueueItemID: "502"
            ))
        )
        #expect(move.endpointPathComponents == ["91", "items", "504", "move"])
        #expect(move.method == "PUT")
        #expect(move.queryItems == [URLQueryItem(name: "after", value: "502")])

        for invalidIdentifier in ["", " ", "item-503", "50/3"] {
            #expect(throws: PlexAPIError.self) {
                _ = try PlexPlayQueueItemMutationRequest(
                    queueID: 91,
                    mutation: .remove(playQueueItemID: invalidIdentifier)
                )
            }
        }
        #expect(throws: PlexAPIError.self) {
            _ = try PlexPlayQueueItemMutationRequest(
                queueID: 91,
                mutation: .move(PlexPlayQueueItemMove(
                    playQueueItemID: "503",
                    afterPlayQueueItemID: "503"
                ))
            )
        }
    }

    @Test(arguments: [0, 2, 5])
    func createsServerAuthoredCinemaQueueWithExactPrefixCount(
        extrasPrefixCount: Int
    ) async throws {
        let capture = RequestCapture()
        let session = makePlayQueueMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Self.cinemaQueueData)
        }
        let movie = try decodeItem(#"{"ratingKey":"77","key":"/library/metadata/77","title":"Feature","type":"movie","Media":[]}"#)

        var queue = try await PlexAPIClient(session: session).createCinemaPlayQueue(
            for: movie,
            extrasPrefixCount: extrasPrefixCount,
            endpointPath: "/provider/play-queue?source=library",
            using: try configuration
        )

        let request = try #require(capture.request)
        let components = try #require(request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        })
        #expect(request.httpMethod == "POST")
        #expect(components.path == "/provider/play-queue")
        #expect(queryValue("source", in: components) == "library")
        #expect(queryValue("uri", in: components) == "server://server-id/com.plexapp.plugins.library/library/metadata/77")
        #expect(queryValue("type", in: components) == "video")
        #expect(queryValue("key", in: components) == "/library/metadata/77")
        #expect(queryValue("shuffle", in: components) == "0")
        #expect(queryValue("repeat", in: components) == "0")
        #expect(queryValue("continuous", in: components) == "0")
        #expect(queryValue("extrasPrefixCount", in: components) == String(extrasPrefixCount))
        #expect(queue.purpose == .cinemaPreplay(primaryRatingKey: "77"))
        #expect(queue.isCinemaPreplayQueue)
        #expect(queue.currentItem.ratingKey == "700")
        #expect(queue.isCurrentCinemaPreplayItem)
        #expect(!queue.canChangeShuffle)
        #expect(!queue.canRepeatAll)
        #expect(!queue.canAdd(movie))
        #expect(queue.move(.next)?.ratingKey == "77")
        #expect(queue.isCinemaPreplayQueue)
        #expect(!queue.isCurrentCinemaPreplayItem)
    }

    @Test func rejectsCinemaQueueRequestsOutsideTheMovieClientContract() async throws {
        let movie = try decodeItem(#"{"ratingKey":"77","key":"/library/metadata/77","title":"Feature","type":"movie","Media":[]}"#)
        let episode = try decodeItem(#"{"ratingKey":"78","key":"/library/metadata/78","title":"Episode","type":"episode","Media":[]}"#)

        for invalidCount in [-1, 6] {
            await #expect(throws: PlexAPIError.self) {
                _ = try await PlexAPIClient().createCinemaPlayQueue(
                    for: movie,
                    extrasPrefixCount: invalidCount,
                    endpointPath: "/playQueues",
                    using: try configuration
                )
            }
        }
        await #expect(throws: PlexAPIError.self) {
            _ = try await PlexAPIClient().createCinemaPlayQueue(
                for: episode,
                extrasPrefixCount: 1,
                endpointPath: "/playQueues",
                using: try configuration
            )
        }
    }

    @Test func createsContinuousEpisodeQueueFromDocumentedServerSourceURI() async throws {
        let capture = RequestCapture()
        let session = makePlayQueueMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Self.queueData)
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "key": "/library/metadata/42",
          "title": "Current Episode",
          "type": "episode",
          "Media": []
        }
        """#)

        let queue = try await PlexAPIClient(session: session).createContinuousPlayQueue(
            for: item,
            endpointPath: "/playQueues",
            using: try configuration
        )

        let request = try #require(capture.request)
        let components = try #require(request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        })
        #expect(request.httpMethod == "POST")
        #expect(components.path == "/playQueues")
        #expect(queryValue("uri", in: components) == "server://server-id/com.plexapp.plugins.library/library/metadata/42")
        #expect(queryValue("type", in: components) == "video")
        #expect(queryValue("key", in: components) == "/library/metadata/42")
        #expect(queryValue("continuous", in: components) == "1")
        #expect(queryValue("shuffle", in: components) == "0")
        #expect(queryValue("repeat", in: components) == "0")
        #expect(request.value(forHTTPHeaderField: "X-Plex-Pms-Api-Version") == "1.0.0")
        #expect(queue.id == 91)
        #expect(queue.currentItem.ratingKey == "42")
        #expect(queue.canMovePrevious)
        #expect(queue.canMoveNext)
        #expect(queue.previousItem?.ratingKey == "41")
        #expect(queue.nextItem?.ratingKey == "43")
    }

    @Test func createsContinuousTrackQueueAsDocumentedAudioType() async throws {
        let capture = RequestCapture()
        let session = makePlayQueueMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Self.audioQueueData)
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "82",
          "key": "/library/metadata/82",
          "title": "Chapter 2",
          "type": "track",
          "Media": []
        }
        """#)

        let queue = try await PlexAPIClient(session: session).createContinuousPlayQueue(
            for: item,
            endpointPath: "/provider/play-queue?source=library",
            using: try configuration
        )

        let request = try #require(capture.request)
        let components = try #require(request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        })
        #expect(request.httpMethod == "POST")
        #expect(components.path == "/provider/play-queue")
        #expect(queryValue("source", in: components) == "library")
        #expect(queryValue("uri", in: components) == "server://server-id/com.plexapp.plugins.library/library/metadata/82")
        #expect(queryValue("type", in: components) == "audio")
        #expect(queryValue("key", in: components) == "/library/metadata/82")
        #expect(queryValue("continuous", in: components) == "1")
        #expect(queryValue("shuffle", in: components) == "0")
        #expect(queryValue("repeat", in: components) == "0")
        #expect(queue.currentItem.ratingKey == "82")
        #expect(queue.canMovePrevious)
        #expect(queue.canMoveNext)
    }

    @Test func createsShowQueueAtTheServerAuthoritativeOnDeckEpisode() async throws {
        let capture = RequestCapture()
        let session = makePlayQueueMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Self.queueData)
        }
        let show = try decodeItem(#"{"ratingKey":"7","key":"/library/metadata/7/children","title":"Show","type":"show","Media":[]}"#)

        let queue = try await PlexAPIClient(session: session).createContinuousPlayQueue(
            for: show,
            endpointPath: "/provider/play-queue?source=library",
            using: try configuration
        )

        let request = try #require(capture.request)
        let components = try #require(request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        })
        #expect(request.httpMethod == "POST")
        #expect(components.path == "/provider/play-queue")
        #expect(queryValue("source", in: components) == "library")
        #expect(queryValue("uri", in: components) == "server://server-id/com.plexapp.plugins.library/library/metadata/7/children")
        #expect(queryValue("type", in: components) == "video")
        #expect(queryValue("continuous", in: components) == "1")
        #expect(queryValue("onDeck", in: components) == "1")
        #expect(queryValue("key", in: components) == nil)
        #expect(queue.currentItem.playQueueItemID == "502")
        #expect(queue.currentItem.ratingKey == "42")
    }

    @Test func onlyShowsAndSeasonsExposeHierarchyOnDeckPlayback() throws {
        let show = try decodeItem(#"{"ratingKey":"7","key":"/library/metadata/7/children","title":"Show","type":"show"}"#)
        let season = try decodeItem(#"{"ratingKey":"8","key":"/library/metadata/8/children","title":"Season 1","type":"season"}"#)
        let episode = try decodeItem(#"{"ratingKey":"9","key":"/library/metadata/9","title":"Episode","type":"episode"}"#)
        let showWithoutKey = try decodeItem(#"{"ratingKey":"10","title":"Show","type":"show"}"#)

        #expect(show.continuousPlayQueueType == .video)
        #expect(season.continuousPlayQueueType == .video)
        #expect(show.continuousPlayQueueUsesOnDeck)
        #expect(season.continuousPlayQueueUsesOnDeck)
        #expect(show.supportsHierarchyPlayback)
        #expect(season.supportsHierarchyPlayback)
        #expect(!episode.continuousPlayQueueUsesOnDeck)
        #expect(!episode.supportsHierarchyPlayback)
        #expect(!showWithoutKey.supportsHierarchyPlayback)
    }

    @Test func rejectsItemsThatDoNotHaveContinuousQueueSemantics() async throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "7",
          "key": "/library/metadata/7",
          "title": "Standalone Movie",
          "type": "movie",
          "Media": []
        }
        """#)

        await #expect(throws: PlexAPIError.self) {
            _ = try await PlexAPIClient().createContinuousPlayQueue(
                for: item,
                endpointPath: "/playQueues",
                using: try configuration
            )
        }
    }

    @Test func refreshesAQueueWindowAroundTheExactCurrentQueueItem() async throws {
        let capture = RequestCapture()
        let session = makePlayQueueMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Self.queueData)
        }

        let page = try await PlexAPIClient(session: session).fetchPlayQueuePage(
            queueID: 91,
            endpointPath: "/provider/play-queue?source=library",
            centeredOn: "502",
            window: 40,
            using: try configuration
        )

        let request = try #require(capture.request)
        let components = try #require(request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        })
        #expect(request.httpMethod == "GET")
        #expect(components.path == "/provider/play-queue/91")
        #expect(queryValue("source", in: components) == "library")
        #expect(queryValue("center", in: components) == "502")
        #expect(queryValue("window", in: components) == "40")
        #expect(queryValue("includeBefore", in: components) == "1")
        #expect(queryValue("includeAfter", in: components) == "1")
        #expect(page.items.map(\.playQueueItemID) == ["501", "502", "503"])
    }

    @Test func addsItemsThroughTheExactAdvertisedQueueEndpoint() async throws {
        let capture = RequestCapture()
        let session = makePlayQueueMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Self.queueData)
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "77",
          "key": "/library/metadata/77",
          "title": "Queued Movie",
          "type": "movie",
          "Media": []
        }
        """#)
        let client = PlexAPIClient(session: session)

        for (insertion, expectedNext) in [
            (PlexPlayQueueInsertion.next, "1"),
            (.upNext, "0"),
        ] {
            _ = try await client.addToPlayQueue(
                item,
                queueID: 91,
                insertion: insertion,
                endpointPath: "/provider/play-queue?source=library",
                using: try configuration
            )

            let request = try #require(capture.request)
            let components = try #require(request.url.flatMap {
                URLComponents(url: $0, resolvingAgainstBaseURL: false)
            })
            #expect(request.httpMethod == "PUT")
            #expect(components.path == "/provider/play-queue/91")
            #expect(queryValue("source", in: components) == "library")
            #expect(queryValue("uri", in: components) == "server://server-id/com.plexapp.plugins.library/library/metadata/77")
            #expect(queryValue("next", in: components) == expectedNext)
        }
    }

    @Test func removesAnUpcomingItemThroughTheExactAdvertisedQueueEndpoint() async throws {
        let capture = RequestCapture()
        let session = makePlayQueueMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Self.removedQueueItemData)
        }

        let page = try await PlexAPIClient(session: session).removePlayQueueItem(
            queueID: 91,
            playQueueItemID: "504",
            endpointPath: "/provider/play-queue?source=library",
            using: try configuration
        )

        let request = try #require(capture.request)
        let components = try #require(request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        })
        #expect(request.httpMethod == "DELETE")
        #expect(components.path == "/provider/play-queue/91/items/504")
        #expect(queryValue("source", in: components) == "library")
        #expect(page.items.map(\.playQueueItemID) == ["501", "502", "503", "505"])
    }

    @Test func movesAnUpcomingItemAfterTheExactServerQueueItem() async throws {
        let capture = RequestCapture()
        let session = makePlayQueueMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Self.movedQueueItemData)
        }
        let move = PlexPlayQueueItemMove(
            playQueueItemID: "504",
            afterPlayQueueItemID: "502"
        )

        let page = try await PlexAPIClient(session: session).movePlayQueueItem(
            queueID: 91,
            move: move,
            endpointPath: "/provider/play-queue?source=library",
            using: try configuration
        )

        let request = try #require(capture.request)
        let components = try #require(request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        })
        #expect(request.httpMethod == "PUT")
        #expect(components.path == "/provider/play-queue/91/items/504/move")
        #expect(queryValue("source", in: components) == "library")
        #expect(queryValue("after", in: components) == "502")
        #expect(page.items.map(\.playQueueItemID) == ["501", "502", "504", "503", "505"])
    }

    @Test func rejectsNonNumericPlayQueueMutationIdentifiers() async throws {
        await #expect(throws: PlexAPIError.self) {
            _ = try await PlexAPIClient().removePlayQueueItem(
                queueID: 91,
                playQueueItemID: "not-an-id",
                endpointPath: "/playQueues",
                using: try configuration
            )
        }
        await #expect(throws: PlexAPIError.self) {
            _ = try await PlexAPIClient().movePlayQueueItem(
                queueID: 91,
                move: PlexPlayQueueItemMove(
                    playQueueItemID: "504",
                    afterPlayQueueItemID: "other"
                ),
                endpointPath: "/playQueues",
                using: try configuration
            )
        }
    }

    @Test func changesShuffleThroughTheExactAdvertisedQueueEndpoint() async throws {
        let capture = RequestCapture()
        let session = makePlayQueueMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = request.url?.path.hasSuffix("/unshuffle") == true
                ? Self.unshuffledQueueData
                : Self.shuffledQueueData
            return (response, data)
        }
        let client = PlexAPIClient(session: session)

        let shuffledPage = try await client.setPlayQueueShuffled(
            true,
            queueID: 91,
            endpointPath: "/provider/play-queue?source=library",
            using: try configuration
        )

        var request = try #require(capture.request)
        var components = try #require(request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        })
        #expect(request.httpMethod == "PUT")
        #expect(components.path == "/provider/play-queue/91/shuffle")
        #expect(queryValue("source", in: components) == "library")
        #expect(shuffledPage.isShuffled == true)
        #expect(shuffledPage.selectedItemID == "502")

        let unshuffledPage = try await client.setPlayQueueShuffled(
            false,
            queueID: 91,
            endpointPath: "/provider/play-queue?source=library",
            using: try configuration
        )

        request = try #require(capture.request)
        components = try #require(request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        })
        #expect(request.httpMethod == "PUT")
        #expect(components.path == "/provider/play-queue/91/unshuffle")
        #expect(queryValue("source", in: components) == "library")
        #expect(unshuffledPage.isShuffled == false)
        #expect(unshuffledPage.selectedItemID == "502")
    }

    @Test func resetsQueueThroughTheExactAdvertisedQueueEndpoint() async throws {
        let capture = RequestCapture()
        let session = makePlayQueueMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Self.resetQueueData)
        }

        let page = try await PlexAPIClient(session: session).resetPlayQueue(
            queueID: 91,
            endpointPath: "/provider/play-queue?source=library",
            using: try configuration
        )

        let request = try #require(capture.request)
        let components = try #require(request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        })
        #expect(request.httpMethod == "PUT")
        #expect(components.path == "/provider/play-queue/91/reset")
        #expect(queryValue("source", in: components) == "library")
        #expect(page.selectedItemID == "501")
        #expect(page.selectedItemOffset == 0)
    }

    @Test func appliesOnlyAuthoritativeShuffleResponsesThatPreserveTheCurrentItem() throws {
        let naturalItems = try decodeItems(#"""
        [
          {"ratingKey":"41","title":"Previous","playQueueItemID":"501","Media":[]},
          {"ratingKey":"42","title":"Current","playQueueItemID":"502","Media":[]},
          {"ratingKey":"43","title":"Next","playQueueItemID":"503","Media":[]}
        ]
        """#)
        var queue = try PlexPlaybackQueue(
            page: PlexPlayQueuePage(
                id: 91,
                version: 1,
                totalCount: 3,
                offset: 0,
                selectedItemID: "502",
                selectedItemOffset: 1,
                items: naturalItems,
                isShuffled: false
            ),
            selectedRatingKey: "42"
        )
        let shuffledItems = try decodeItems(#"""
        [
          {"ratingKey":"43","title":"Next","playQueueItemID":"503","Media":[]},
          {"ratingKey":"42","title":"Current","playQueueItemID":"502","Media":[]},
          {"ratingKey":"41","title":"Previous","playQueueItemID":"501","Media":[]}
        ]
        """#)

        try queue.applyShuffleMutation(
            PlexPlayQueuePage(
                id: 91,
                version: 2,
                totalCount: 3,
                offset: 0,
                selectedItemID: "502",
                selectedItemOffset: 1,
                items: shuffledItems,
                isShuffled: true
            ),
            expectedShuffled: true
        )

        #expect(queue.isShuffled)
        #expect(queue.currentItem.playQueueItemID == "502")
        #expect(queue.presentation.upcomingItems.map(\.playQueueItemID) == ["501"])

        #expect(throws: PlexAPIError.self) {
            try queue.applyShuffleMutation(
                PlexPlayQueuePage(
                    id: 91,
                    version: 3,
                    totalCount: 3,
                    offset: 0,
                    selectedItemID: "503",
                    selectedItemOffset: 0,
                    items: shuffledItems,
                    isShuffled: false
                ),
                expectedShuffled: false
            )
        }
        #expect(queue.isShuffled)
        #expect(queue.currentItem.playQueueItemID == "502")

        #expect(throws: PlexAPIError.self) {
            try queue.applyShuffleMutation(
                PlexPlayQueuePage(
                    id: 91,
                    version: 3,
                    totalCount: 3,
                    offset: 0,
                    selectedItemID: "502",
                    selectedItemOffset: 1,
                    items: shuffledItems
                ),
                expectedShuffled: false
            )
        }
        #expect(queue.isShuffled)
        #expect(queue.currentItem.playQueueItemID == "502")
    }

    @Test func derivesOnlyLoadedUpcomingQueueEditRequests() throws {
        let items = try decodeItems(#"""
        [
          {"ratingKey":"41","title":"Previous","playQueueItemID":"501","Media":[]},
          {"ratingKey":"42","title":"Current","playQueueItemID":"502","Media":[]},
          {"ratingKey":"43","title":"First Up Next","playQueueItemID":"503","Media":[]},
          {"ratingKey":"44","title":"Second Up Next","playQueueItemID":"504","Media":[]},
          {"ratingKey":"45","title":"Last Loaded","playQueueItemID":"505","Media":[]}
        ]
        """#)
        let queue = try PlexPlaybackQueue(
            page: PlexPlayQueuePage(
                id: 91,
                version: 1,
                totalCount: 8,
                offset: 0,
                selectedItemID: "502",
                selectedItemOffset: 1,
                items: items
            ),
            selectedRatingKey: "42"
        )

        #expect(!queue.canRemoveUpcomingItem(playQueueItemID: "502"))
        #expect(queue.canRemoveUpcomingItem(playQueueItemID: "503"))
        #expect(queue.moveRequest(for: "503", direction: .up) == nil)
        #expect(queue.moveRequest(for: "503", direction: .down) == PlexPlayQueueItemMove(
            playQueueItemID: "503",
            afterPlayQueueItemID: "504"
        ))
        #expect(queue.moveRequest(for: "504", direction: .up) == PlexPlayQueueItemMove(
            playQueueItemID: "504",
            afterPlayQueueItemID: "502"
        ))
        #expect(queue.moveRequest(for: "505", direction: .down) == nil)
    }

    @Test func derivesAnExactServerMoveFromNativeListOffsets() throws {
        let queue = try editableQueue()

        #expect(queue.canReorderLoadedUpcomingItems)
        #expect(queue.moveRequest(
            fromUpcomingOffsets: IndexSet(integer: 0),
            toUpcomingOffset: 3
        ) == PlexPlayQueueItemMove(
            playQueueItemID: "503",
            afterPlayQueueItemID: "505"
        ))
        #expect(queue.moveRequest(
            fromUpcomingOffsets: IndexSet(integer: 2),
            toUpcomingOffset: 0
        ) == PlexPlayQueueItemMove(
            playQueueItemID: "505",
            afterPlayQueueItemID: "502"
        ))
        #expect(queue.moveRequest(
            fromUpcomingOffsets: IndexSet(integer: 1),
            toUpcomingOffset: 2
        ) == nil)
        #expect(queue.moveRequest(
            fromUpcomingOffsets: IndexSet([0, 1]),
            toUpcomingOffset: 3
        ) == nil)
        #expect(queue.moveRequest(
            fromUpcomingOffsets: IndexSet(integer: 0),
            toUpcomingOffset: 4
        ) == nil)
    }

    @Test func appliesOnlyServerConfirmedRemovalThatPreservesNowPlaying() throws {
        var queue = try editableQueue()
        let removedItems = try decodeItems(#"""
        [
          {"ratingKey":"41","title":"Previous","playQueueItemID":"501","Media":[]},
          {"ratingKey":"42","title":"Current","playQueueItemID":"502","Media":[]},
          {"ratingKey":"43","title":"First Up Next","playQueueItemID":"503","Media":[]},
          {"ratingKey":"45","title":"Last Up Next","playQueueItemID":"505","Media":[]}
        ]
        """#)

        try queue.applyRemoval(
            PlexPlayQueuePage(
                id: 91,
                version: 2,
                totalCount: 4,
                offset: 0,
                selectedItemID: "502",
                selectedItemOffset: 1,
                items: removedItems
            ),
            removedPlayQueueItemID: "504"
        )

        #expect(queue.currentItem.playQueueItemID == "502")
        #expect(queue.totalCount == 4)
        #expect(queue.presentation.upcomingItems.map(\.playQueueItemID) == ["503", "505"])

        #expect(throws: PlexAPIError.self) {
            try queue.applyRemoval(
                PlexPlayQueuePage(
                    id: 91,
                    version: 3,
                    totalCount: 3,
                    offset: 0,
                    selectedItemID: "503",
                    selectedItemOffset: 1,
                    items: removedItems
                ),
                removedPlayQueueItemID: "505"
            )
        }
        #expect(queue.currentItem.playQueueItemID == "502")
    }

    @Test func appliesOnlyServerConfirmedMoveThatPreservesNowPlaying() throws {
        var queue = try editableQueue()
        let move = try #require(queue.moveRequest(for: "504", direction: .up))
        let movedItems = try decodeItems(#"""
        [
          {"ratingKey":"41","title":"Previous","playQueueItemID":"501","Media":[]},
          {"ratingKey":"42","title":"Current","playQueueItemID":"502","Media":[]},
          {"ratingKey":"44","title":"Second Up Next","playQueueItemID":"504","Media":[]},
          {"ratingKey":"43","title":"First Up Next","playQueueItemID":"503","Media":[]},
          {"ratingKey":"45","title":"Last Up Next","playQueueItemID":"505","Media":[]}
        ]
        """#)

        try queue.applyMove(
            PlexPlayQueuePage(
                id: 91,
                version: 2,
                totalCount: 5,
                offset: 0,
                selectedItemID: "502",
                selectedItemOffset: 1,
                items: movedItems
            ),
            request: move
        )

        #expect(queue.currentItem.playQueueItemID == "502")
        #expect(queue.presentation.upcomingItems.map(\.playQueueItemID) == ["504", "503", "505"])

        #expect(throws: PlexAPIError.self) {
            try queue.applyMove(
                PlexPlayQueuePage(
                    id: 91,
                    version: 3,
                    totalCount: 5,
                    offset: 0,
                    selectedItemID: "502",
                    selectedItemOffset: 1,
                    items: movedItems
                ),
                request: PlexPlayQueueItemMove(
                    playQueueItemID: "503",
                    afterPlayQueueItemID: "505"
                )
            )
        }
        #expect(queue.presentation.upcomingItems.map(\.playQueueItemID) == ["504", "503", "505"])
    }

    @Test func appliesAConfirmedArbitraryLoadedMove() throws {
        var queue = try editableQueue()
        let move = try #require(queue.moveRequest(
            fromUpcomingOffsets: IndexSet(integer: 0),
            toUpcomingOffset: 3
        ))
        let movedItems = try decodeItems(#"""
        [
          {"ratingKey":"41","title":"Previous","playQueueItemID":"501","Media":[]},
          {"ratingKey":"42","title":"Current","playQueueItemID":"502","Media":[]},
          {"ratingKey":"44","title":"Second Up Next","playQueueItemID":"504","Media":[]},
          {"ratingKey":"45","title":"Last Up Next","playQueueItemID":"505","Media":[]},
          {"ratingKey":"43","title":"First Up Next","playQueueItemID":"503","Media":[]}
        ]
        """#)

        try queue.applyMove(
            PlexPlayQueuePage(
                id: 91,
                version: 2,
                totalCount: 5,
                offset: 0,
                selectedItemID: "502",
                selectedItemOffset: 1,
                items: movedItems
            ),
            request: move
        )

        #expect(queue.currentItem.playQueueItemID == "502")
        #expect(queue.presentation.upcomingItems.map(\.playQueueItemID) == ["504", "505", "503"])
    }

    @Test func cinemaPreplayQueuesCannotBeEdited() throws {
        let items = try decodeItems(#"""
        [
          {"ratingKey":"700","title":"Trailer","playQueueItemID":"701","Media":[]},
          {"ratingKey":"77","title":"Feature","playQueueItemID":"702","Media":[]}
        ]
        """#)
        let queue = try PlexPlaybackQueue(
            page: PlexPlayQueuePage(
                id: 93,
                version: 1,
                totalCount: 2,
                offset: 0,
                selectedItemID: "701",
                selectedItemOffset: 0,
                items: items
            ),
            selectedRatingKey: "700",
            purpose: .cinemaPreplay(primaryRatingKey: "77")
        )

        #expect(!queue.canRemoveUpcomingItem(playQueueItemID: "702"))
        #expect(!queue.canReorderLoadedUpcomingItems)
        #expect(queue.moveRequest(for: "702", direction: .up) == nil)
        #expect(queue.moveRequest(for: "702", direction: .down) == nil)
    }

    @Test func disablesShuffleWhenPlexReturnsAnUpNextRegion() throws {
        let items = try decodeItems(#"""
        [
          {"ratingKey":"42","title":"Current","playQueueItemID":"502","Media":[]},
          {"ratingKey":"43","title":"Queued Next","playQueueItemID":"503","Media":[]}
        ]
        """#)
        let queue = try PlexPlaybackQueue(
            page: PlexPlayQueuePage(
                id: 91,
                version: 2,
                totalCount: 2,
                offset: 0,
                selectedItemID: "502",
                selectedItemOffset: 0,
                items: items,
                isShuffled: false,
                lastAddedItemID: "503"
            ),
            selectedRatingKey: "42"
        )

        #expect(queue.hasUpNextRegion)
        #expect(!queue.canChangeShuffle)
        #expect(!queue.presentation.isShuffled)
    }

    @Test func queueInsertionRequiresCompatibleMediaAndPreservesTheCurrentItem() throws {
        let initialItems = try decodeItems(#"""
        [
          {"ratingKey":"42","key":"/library/metadata/42","title":"Current","type":"episode","playQueueItemID":"502","Media":[]},
          {"ratingKey":"43","key":"/library/metadata/43","title":"Original Next","type":"episode","playQueueItemID":"503","Media":[]}
        ]
        """#)
        var queue = try PlexPlaybackQueue(
            page: PlexPlayQueuePage(
                id: 91,
                version: 1,
                totalCount: 2,
                offset: 0,
                selectedItemID: "502",
                selectedItemOffset: 0,
                items: initialItems
            ),
            selectedRatingKey: "42"
        )
        let movie = try decodeItem(#"{"ratingKey":"77","key":"/library/metadata/77","title":"Movie","type":"movie","Media":[]}"#)
        let track = try decodeItem(#"{"ratingKey":"88","key":"/library/metadata/88","title":"Track","type":"track","Media":[]}"#)
        let missingKey = try decodeItem(#"{"ratingKey":"78","title":"Missing Key","type":"movie","Media":[]}"#)

        #expect(queue.canAdd(movie))
        #expect(!queue.canAdd(track))
        #expect(!queue.canAdd(missingKey))

        let addedItems = try decodeItems(#"""
        [
          {"ratingKey":"42","key":"/library/metadata/42","title":"Current","type":"episode","playQueueItemID":"502","Media":[]},
          {"ratingKey":"77","key":"/library/metadata/77","title":"Queued Movie","type":"movie","playQueueItemID":"504","Media":[]},
          {"ratingKey":"43","key":"/library/metadata/43","title":"Original Next","type":"episode","playQueueItemID":"503","Media":[]}
        ]
        """#)
        try queue.applyAddition(PlexPlayQueuePage(
            id: 91,
            version: 2,
            totalCount: 3,
            offset: 0,
            selectedItemID: "502",
            selectedItemOffset: 0,
            items: addedItems,
            isShuffled: false,
            lastAddedItemID: "504"
        ))

        #expect(queue.currentItem.playQueueItemID == "502")
        #expect(queue.presentation.upcomingItems.map(\.playQueueItemID) == ["504", "503"])
        #expect(queue.hasUpNextRegion)
        #expect(!queue.canChangeShuffle)

        #expect(throws: PlexAPIError.self) {
            try queue.applyAddition(PlexPlayQueuePage(
                id: 91,
                version: 3,
                totalCount: 3,
                offset: 0,
                selectedItemID: "504",
                selectedItemOffset: 1,
                items: addedItems,
                lastAddedItemID: "504"
            ))
        }
        #expect(queue.currentItem.playQueueItemID == "502")
    }

    @Test @MainActor func activeQueueAcceptsItemsOnlyFromItsOriginalServer() throws {
        let defaultsName = "PlexPlayQueueTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let credentials = PlexStoredCredentials(userToken: "", serverToken: "server-token")
        let settings = PlexSettingsStore(
            defaults: defaults,
            credentialStore: PlexMemoryCredentialStore(credentials: credentials),
            initialCredentials: credentials
        )
        settings.selectedServerIdentifier = "server-id"
        let browserStore = PlexBrowserStore(
            connectionStore: PlexConnectionStore(settings: settings),
            playbackCapabilities: PlexPlaybackCapabilities(
                directPlayContainers: [],
                directPlayVideoCodecs: [],
                directPlayAudioCodecs: []
            )
        )
        let currentItems = try decodeItems(#"""
        [
          {"ratingKey":"42","key":"/library/metadata/42","title":"Current","type":"episode","playQueueItemID":"502","Media":[]}
        ]
        """#)
        let queue = try PlexPlaybackQueue(
            page: PlexPlayQueuePage(
                id: 91,
                version: 1,
                totalCount: 1,
                offset: 0,
                selectedItemID: "502",
                selectedItemOffset: 0,
                items: currentItems
            ),
            selectedRatingKey: "42"
        )
        let plan = PlexPlaybackPlan(
            url: try #require(URL(string: "https://plex.local/video.mp4")),
            method: .directPlay,
            mediaKind: .video,
            sessionIdentifier: "queue-server-scope",
            ratingKey: "42",
            duration: 120,
            startTime: 0,
            source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0),
            usesServerMediaSelection: false
        )
        let presentation = PlexPlaybackPresentation(
            item: currentItems[0],
            plan: plan,
            queue: queue,
            videoQuality: .original,
            serverIdentifier: "server-id"
        )
        let coordinator = PlexPlayerCoordinator()
        coordinator.present(presentation)
        let session = coordinator.session(for: presentation, browserStore: browserStore)
        defer { coordinator.close(session) }
        let candidate = try decodeItem(#"{"ratingKey":"77","key":"/library/metadata/77","title":"Movie","type":"movie","Media":[]}"#)

        #expect(session.canAddToQueue(candidate))

        settings.selectedServerIdentifier = "another-server"

        #expect(!session.canAddToQueue(candidate))
    }

    @Test func appliesOnlyAuthoritativeQueueResetsToTheFirstStableItem() throws {
        let items = try decodeItems(#"""
        [
          {"ratingKey":"41","title":"First","playQueueItemID":"501","Media":[]},
          {"ratingKey":"42","title":"Current","playQueueItemID":"502","Media":[]},
          {"ratingKey":"43","title":"Last","playQueueItemID":"503","Media":[]}
        ]
        """#)
        var queue = try PlexPlaybackQueue(
            page: PlexPlayQueuePage(
                id: 91,
                version: 1,
                totalCount: 3,
                offset: 0,
                selectedItemID: "503",
                selectedItemOffset: 2,
                items: items
            ),
            selectedRatingKey: "43"
        )

        try queue.applyReset(PlexPlayQueuePage(
            id: 91,
            version: 2,
            totalCount: 3,
            offset: 0,
            selectedItemID: "501",
            selectedItemOffset: 0,
            items: items
        ))
        #expect(queue.currentAbsoluteIndex == 0)
        #expect(queue.currentItem.playQueueItemID == "501")
        #expect(queue.canRepeatAll)

        #expect(throws: PlexAPIError.self) {
            try queue.applyReset(PlexPlayQueuePage(
                id: 91,
                version: 3,
                totalCount: 3,
                offset: 0,
                selectedItemID: "502",
                selectedItemOffset: 1,
                items: items
            ))
        }
        #expect(queue.currentItem.playQueueItemID == "501")
    }

    @Test func queueNavigationPreservesAbsolutePositionAcrossServerWindows() throws {
        let firstItems = try decodeItems(#"""
        [
          {"ratingKey":"42","title":"Current","playQueueItemID":"502","Media":[]},
          {"ratingKey":"43","title":"Next","playQueueItemID":"503","Media":[]}
        ]
        """#)
        var queue = try PlexPlaybackQueue(
            page: PlexPlayQueuePage(
                id: 91,
                version: 1,
                totalCount: 100,
                offset: 50,
                selectedItemID: "502",
                selectedItemOffset: 50,
                items: firstItems
            ),
            selectedRatingKey: "42"
        )

        #expect(queue.currentAbsoluteIndex == 50)
        #expect(queue.needsWindowRefresh(for: .previous))
        #expect(!queue.needsWindowRefresh(for: .next))
        #expect(queue.move(.next)?.playQueueItemID == "503")
        #expect(queue.currentAbsoluteIndex == 51)

        let refreshedItems = try decodeItems(#"""
        [
          {"ratingKey":"42","title":"Current","playQueueItemID":"502","Media":[]},
          {"ratingKey":"43","title":"Next","playQueueItemID":"503","Media":[]},
          {"ratingKey":"44","title":"After Next","playQueueItemID":"504","Media":[]}
        ]
        """#)
        try queue.replaceWindow(
            with: PlexPlayQueuePage(
                id: 91,
                version: 2,
                totalCount: 100,
                offset: nil,
                selectedItemID: nil,
                selectedItemOffset: nil,
                items: refreshedItems
            ),
            centeredOn: "503"
        )

        #expect(queue.currentAbsoluteIndex == 51)
        #expect(queue.move(.next)?.playQueueItemID == "504")
        #expect(queue.currentAbsoluteIndex == 52)
    }

    @Test func queuePresentationSeparatesLoadedItemsFromItemsRemainingOnServer() throws {
        let items = try decodeItems(#"""
        [
          {"ratingKey":"42","title":"Current","playQueueItemID":"502","Media":[]},
          {"ratingKey":"43","title":"Next","playQueueItemID":"503","Media":[]},
          {"ratingKey":"44","title":"Later","playQueueItemID":"504","Media":[]}
        ]
        """#)
        let queue = try PlexPlaybackQueue(
            page: PlexPlayQueuePage(
                id: 91,
                version: 2,
                totalCount: 100,
                offset: 50,
                selectedItemID: "502",
                selectedItemOffset: 50,
                items: items
            ),
            selectedRatingKey: "42"
        )

        let presentation = queue.presentation
        #expect(presentation.currentItem.playQueueItemID == "502")
        #expect(presentation.upcomingItems.map(\.playQueueItemID) == ["503", "504"])
        #expect(presentation.currentPosition == 51)
        #expect(presentation.totalCount == 100)
        #expect(presentation.remainingCount == 49)
        #expect(presentation.unloadedRemainingCount == 47)
        #expect(presentation.canRemoveUpcomingItems)
        #expect(presentation.canReorderUpcomingItems)
        #expect(presentation.canMoveUpcomingItem(
            playQueueItemID: "503",
            direction: .up
        ) == false)
        #expect(presentation.canMoveUpcomingItem(
            playQueueItemID: "503",
            direction: .down
        ))
        #expect(presentation.canMoveUpcomingItem(
            playQueueItemID: "504",
            direction: .up
        ))
        #expect(presentation.canMoveUpcomingItem(
            playQueueItemID: "504",
            direction: .down
        ) == false)
    }

    @Test func movesDirectlyToAnAuthoritativeLoadedQueueItem() throws {
        let items = try decodeItems(#"""
        [
          {"ratingKey":"42","title":"Current","playQueueItemID":"502","Media":[]},
          {"ratingKey":"43","title":"Next","playQueueItemID":"503","Media":[]},
          {"ratingKey":"44","title":"Later","playQueueItemID":"504","Media":[]}
        ]
        """#)
        var queue = try PlexPlaybackQueue(
            page: PlexPlayQueuePage(
                id: 91,
                version: 2,
                totalCount: 3,
                offset: 0,
                selectedItemID: "502",
                selectedItemOffset: 0,
                items: items
            ),
            selectedRatingKey: "42"
        )

        #expect(queue.move(toPlayQueueItemID: "504")?.ratingKey == "44")
        #expect(queue.currentAbsoluteIndex == 2)
        #expect(queue.presentation.currentPosition == 3)
        #expect(queue.presentation.upcomingItems.isEmpty)
        #expect(queue.move(toPlayQueueItemID: "missing") == nil)
    }

    @Test func rejectsQueueWindowsWithoutStableQueueItemIdentifiers() throws {
        let invalidItems = try decodeItems(#"""
        [
          {"ratingKey":"42","title":"Current","Media":[]},
          {"ratingKey":"43","title":"Next","playQueueItemID":"503","Media":[]}
        ]
        """#)

        #expect(throws: PlexAPIError.self) {
            _ = try PlexPlaybackQueue(
                page: PlexPlayQueuePage(
                    id: 91,
                    version: 1,
                    totalCount: 2,
                    offset: 0,
                    selectedItemID: nil,
                    selectedItemOffset: 0,
                    items: invalidItems
                ),
                selectedRatingKey: "42"
            )
        }

        let duplicateItems = try decodeItems(#"""
        [
          {"ratingKey":"42","title":"Current","playQueueItemID":"502","Media":[]},
          {"ratingKey":"43","title":"Next","playQueueItemID":"502","Media":[]}
        ]
        """#)
        #expect(throws: PlexAPIError.self) {
            _ = try PlexPlaybackQueue(
                page: PlexPlayQueuePage(
                    id: 91,
                    version: 1,
                    totalCount: 2,
                    offset: 0,
                    selectedItemID: "502",
                    selectedItemOffset: 0,
                    items: duplicateItems
                ),
                selectedRatingKey: "42"
            )
        }
    }

    @Test func rejectsReplacementWindowsWithoutStableQueueItemIdentifiers() throws {
        let validItems = try decodeItems(#"""
        [
          {"ratingKey":"42","title":"Current","playQueueItemID":"502","Media":[]}
        ]
        """#)
        var queue = try PlexPlaybackQueue(
            page: PlexPlayQueuePage(
                id: 91,
                version: 1,
                totalCount: 2,
                offset: 0,
                selectedItemID: "502",
                selectedItemOffset: 0,
                items: validItems
            ),
            selectedRatingKey: "42"
        )
        let invalidItems = try decodeItems(#"""
        [
          {"ratingKey":"42","title":"Current","playQueueItemID":"502","Media":[]},
          {"ratingKey":"43","title":"Next","Media":[]}
        ]
        """#)

        #expect(throws: PlexAPIError.self) {
            try queue.replaceWindow(
                with: PlexPlayQueuePage(
                    id: 91,
                    version: 2,
                    totalCount: 2,
                    offset: 0,
                    selectedItemID: "502",
                    selectedItemOffset: 0,
                    items: invalidItems
                ),
                centeredOn: "502"
            )
        }


        let duplicateItems = try decodeItems(#"""
        [
          {"ratingKey":"42","title":"Current","playQueueItemID":"502","Media":[]},
          {"ratingKey":"43","title":"Next","playQueueItemID":"502","Media":[]}
        ]
        """#)
        #expect(throws: PlexAPIError.self) {
            try queue.replaceWindow(
                with: PlexPlayQueuePage(
                    id: 91,
                    version: 2,
                    totalCount: 2,
                    offset: 0,
                    selectedItemID: "502",
                    selectedItemOffset: 0,
                    items: duplicateItems
                ),
                centeredOn: "502"
            )
        }
    }

    @Test func marksCompletedMetadataPlayedWithTheDiscoveredPutContract() async throws {
        let capture = RequestCapture()
        let session = makePlayQueueMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data())
        }

        try await PlexAPIClient(session: session).setWatched(
            true,
            ratingKey: "42",
            endpoints: timelineEndpoints,
            using: try configuration
        )

        let request = try #require(capture.request)
        let components = try #require(request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        })
        #expect(request.httpMethod == "PUT")
        #expect(components.path == "/provider/played")
        #expect(queryValue("identifier", in: components) == "custom.library.provider")
        #expect(queryValue("key", in: components) == "42")
    }

    @Test func marksMetadataUnplayedWithTheDiscoveredPutContract() async throws {
        let capture = RequestCapture()
        let session = makePlayQueueMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data())
        }

        try await PlexAPIClient(session: session).setWatched(
            false,
            ratingKey: "42",
            endpoints: timelineEndpoints,
            using: try configuration
        )

        let request = try #require(capture.request)
        let components = try #require(request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        })
        #expect(request.httpMethod == "PUT")
        #expect(components.path == "/provider/unplayed")
        #expect(queryValue("identifier", in: components) == "custom.library.provider")
        #expect(queryValue("key", in: components) == "42")
    }

    @Test func rejectsWatchedMutationWhenTheProviderDoesNotAdvertiseIt() async throws {
        let endpoints = PlexLibraryProviderEndpoints(
            providerIdentifier: "custom.library.provider",
            timelinePath: nil,
            scrobblePath: nil,
            unscrobblePath: nil,
            playQueuePath: "/provider/play-queue",
            ratePath: nil,
            metadataPath: nil,
            removeFromContinueWatchingPath: nil,
            canManage: false
        )

        await #expect(throws: PlexAPIError.self) {
            try await PlexAPIClient().setWatched(
                true,
                ratingKey: "42",
                endpoints: endpoints,
                using: try configuration
            )
        }
    }

    private var timelineEndpoints: PlexLibraryProviderEndpoints {
        PlexLibraryProviderEndpoints(
            providerIdentifier: "custom.library.provider",
            timelinePath: "/provider/timeline",
            scrobblePath: "/provider/played",
            unscrobblePath: "/provider/unplayed",
            playQueuePath: "/provider/play-queue",
            ratePath: nil,
            metadataPath: nil,
            removeFromContinueWatchingPath: nil,
            canManage: false
        )
    }

    private var configuration: PlexConnectionConfiguration {
        get throws {
            PlexConnectionConfiguration(
                serverURL: try #require(URL(string: "https://plex.local:32400")),
                token: "server-token",
                clientContext: PlexClientContext(clientIdentifier: "client-123"),
                serverIdentifier: "server-id"
            )
        }
    }

    private func queryValue(_ name: String, in components: URLComponents) -> String? {
        components.queryItems?.first { $0.name == name }?.value
    }

    private func decodeItem(_ json: String) throws -> PlexMediaItem {
        try JSONDecoder().decode(PlexMediaItem.self, from: Data(json.utf8))
    }

    private func decodeItems(_ json: String) throws -> [PlexMediaItem] {
        try JSONDecoder().decode([PlexMediaItem].self, from: Data(json.utf8))
    }

    private func editableQueue() throws -> PlexPlaybackQueue {
        let items = try decodeItems(#"""
        [
          {"ratingKey":"41","title":"Previous","playQueueItemID":"501","Media":[]},
          {"ratingKey":"42","title":"Current","playQueueItemID":"502","Media":[]},
          {"ratingKey":"43","title":"First Up Next","playQueueItemID":"503","Media":[]},
          {"ratingKey":"44","title":"Second Up Next","playQueueItemID":"504","Media":[]},
          {"ratingKey":"45","title":"Last Up Next","playQueueItemID":"505","Media":[]}
        ]
        """#)
        return try PlexPlaybackQueue(
            page: PlexPlayQueuePage(
                id: 91,
                version: 1,
                totalCount: 5,
                offset: 0,
                selectedItemID: "502",
                selectedItemOffset: 1,
                items: items
            ),
            selectedRatingKey: "42"
        )
    }

    private static let queueData = Data(#"""
    {
      "MediaContainer": {
        "playQueueID": "91",
        "playQueueVersion": "3",
        "playQueueTotalCount": "3",
        "playQueueSelectedItemID": "502",
        "playQueueSelectedItemOffset": "1",
        "offset": "0",
        "Metadata": [
          {"ratingKey":"41","key":"/library/metadata/41","title":"Previous","type":"episode","playQueueItemID":"501","Media":[]},
          {"ratingKey":"42","key":"/library/metadata/42","title":"Current","type":"episode","playQueueItemID":"502","Media":[]},
          {"ratingKey":"43","key":"/library/metadata/43","title":"Next","type":"episode","playQueueItemID":"503","Media":[]}
        ]
      }
    }
    """#.utf8)

    private static let cinemaQueueData = Data(#"""
    {
      "MediaContainer": {
        "playQueueID": "93",
        "playQueueVersion": "1",
        "playQueueTotalCount": "2",
        "playQueueSelectedItemID": "701",
        "playQueueSelectedItemOffset": "0",
        "offset": "0",
        "Metadata": [
          {"ratingKey":"700","key":"/library/metadata/700","title":"Trailer","type":"clip","subtype":"trailer","playQueueItemID":"701","Media":[]},
          {"ratingKey":"77","key":"/library/metadata/77","title":"Feature","type":"movie","playQueueItemID":"702","Media":[]}
        ]
      }
    }
    """#.utf8)

    private static let audioQueueData = Data(#"""
    {
      "MediaContainer": {
        "playQueueID": "92",
        "playQueueVersion": "1",
        "playQueueTotalCount": "3",
        "playQueueSelectedItemID": "602",
        "playQueueSelectedItemOffset": "1",
        "offset": "0",
        "Metadata": [
          {"ratingKey":"81","key":"/library/metadata/81","title":"Chapter 1","type":"track","playQueueItemID":"601","Media":[]},
          {"ratingKey":"82","key":"/library/metadata/82","title":"Chapter 2","type":"track","playQueueItemID":"602","Media":[]},
          {"ratingKey":"83","key":"/library/metadata/83","title":"Chapter 3","type":"track","playQueueItemID":"603","Media":[]}
        ]
      }
    }
    """#.utf8)

    private static let shuffledQueueData = Data(#"""
    {
      "MediaContainer": {
        "playQueueID": "91",
        "playQueueVersion": "4",
        "playQueueTotalCount": "3",
        "playQueueSelectedItemID": "502",
        "playQueueSelectedItemOffset": "1",
        "playQueueShuffled": "1",
        "offset": "0",
        "Metadata": [
          {"ratingKey":"43","key":"/library/metadata/43","title":"Next","type":"episode","playQueueItemID":"503","Media":[]},
          {"ratingKey":"42","key":"/library/metadata/42","title":"Current","type":"episode","playQueueItemID":"502","Media":[]},
          {"ratingKey":"41","key":"/library/metadata/41","title":"Previous","type":"episode","playQueueItemID":"501","Media":[]}
        ]
      }
    }
    """#.utf8)

    private static let unshuffledQueueData = Data(#"""
    {
      "MediaContainer": {
        "playQueueID": "91",
        "playQueueVersion": "5",
        "playQueueTotalCount": "3",
        "playQueueSelectedItemID": "502",
        "playQueueSelectedItemOffset": "1",
        "playQueueShuffled": false,
        "offset": "0",
        "Metadata": [
          {"ratingKey":"41","key":"/library/metadata/41","title":"Previous","type":"episode","playQueueItemID":"501","Media":[]},
          {"ratingKey":"42","key":"/library/metadata/42","title":"Current","type":"episode","playQueueItemID":"502","Media":[]},
          {"ratingKey":"43","key":"/library/metadata/43","title":"Next","type":"episode","playQueueItemID":"503","Media":[]}
        ]
      }
    }
    """#.utf8)

    private static let resetQueueData = Data(#"""
    {
      "MediaContainer": {
        "playQueueID": "91",
        "playQueueVersion": "6",
        "playQueueTotalCount": "3",
        "playQueueSelectedItemID": "501",
        "playQueueSelectedItemOffset": "0",
        "playQueueShuffled": false,
        "offset": "0",
        "Metadata": [
          {"ratingKey":"41","key":"/library/metadata/41","title":"First","type":"episode","playQueueItemID":"501","Media":[]},
          {"ratingKey":"42","key":"/library/metadata/42","title":"Middle","type":"episode","playQueueItemID":"502","Media":[]},
          {"ratingKey":"43","key":"/library/metadata/43","title":"Last","type":"episode","playQueueItemID":"503","Media":[]}
        ]
      }
    }
    """#.utf8)

    private static let removedQueueItemData = Data(#"""
    {
      "MediaContainer": {
        "playQueueID": "91",
        "playQueueVersion": "2",
        "playQueueTotalCount": "4",
        "playQueueSelectedItemID": "502",
        "playQueueSelectedItemOffset": "1",
        "offset": "0",
        "Metadata": [
          {"ratingKey":"41","key":"/library/metadata/41","title":"Previous","type":"episode","playQueueItemID":"501","Media":[]},
          {"ratingKey":"42","key":"/library/metadata/42","title":"Current","type":"episode","playQueueItemID":"502","Media":[]},
          {"ratingKey":"43","key":"/library/metadata/43","title":"First Up Next","type":"episode","playQueueItemID":"503","Media":[]},
          {"ratingKey":"45","key":"/library/metadata/45","title":"Last Up Next","type":"episode","playQueueItemID":"505","Media":[]}
        ]
      }
    }
    """#.utf8)

    private static let movedQueueItemData = Data(#"""
    {
      "MediaContainer": {
        "playQueueID": "91",
        "playQueueVersion": "2",
        "playQueueTotalCount": "5",
        "playQueueSelectedItemID": "502",
        "playQueueSelectedItemOffset": "1",
        "offset": "0",
        "Metadata": [
          {"ratingKey":"41","key":"/library/metadata/41","title":"Previous","type":"episode","playQueueItemID":"501","Media":[]},
          {"ratingKey":"42","key":"/library/metadata/42","title":"Current","type":"episode","playQueueItemID":"502","Media":[]},
          {"ratingKey":"44","key":"/library/metadata/44","title":"Second Up Next","type":"episode","playQueueItemID":"504","Media":[]},
          {"ratingKey":"43","key":"/library/metadata/43","title":"First Up Next","type":"episode","playQueueItemID":"503","Media":[]},
          {"ratingKey":"45","key":"/library/metadata/45","title":"Last Up Next","type":"episode","playQueueItemID":"505","Media":[]}
        ]
      }
    }
    """#.utf8)
}

private func makePlayQueueMockSession(
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    PlayQueueMockURLProtocol.requestHandler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PlayQueueMockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class PlayQueueMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
