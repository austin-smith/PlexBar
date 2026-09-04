import AppKit
import CoreGraphics
import Foundation
import MediaPlayer
import Testing
@testable import PlexBar

struct PlexNowPlayingMetadataTests {
    @Test func episodePublishesItsPlexHierarchyAndPlaybackState() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "episode-42",
          "title": "The We We Are",
          "type": "episode",
          "grandparentRatingKey": "show-7",
          "parentRatingKey": "season-1",
          "grandparentTitle": "Severance",
          "parentTitle": "Season 1",
          "Genre": [{"tag":"Drama"},{"tag":"Science Fiction"}]
        }
        """#)

        let metadata = PlexNowPlayingMetadata(
            item: item,
            duration: 2_400,
            elapsedTime: 125.5,
            playbackRate: 1.5,
            defaultPlaybackRate: 1.5,
            serverIdentifier: "server-a",
            queuePosition: 3,
            queueCount: 10
        )

        #expect(metadata.title == "The We We Are")
        #expect(metadata.artist == "Severance")
        #expect(metadata.albumTitle == "Season 1")
        #expect(metadata.mediaKind == .television)
        #expect(metadata.duration == 2_400)
        #expect(metadata.elapsedTime == 125.5)
        #expect(metadata.playbackRate == 1.5)
        #expect(metadata.defaultPlaybackRate == 1.5)
        #expect(metadata.genre == "Drama, Science Fiction")
        #expect(metadata.externalContentIdentifier == "plex:8:server-a:10:episode-42")
        #expect(metadata.collectionIdentifier == "plex:8:server-a:6:show-7")
        #expect(metadata.queueIndex == 2)
        #expect(metadata.queueCount == 10)

        let info = metadata.nowPlayingInfo
        #expect(info[MPMediaItemPropertyTitle] as? String == "The We We Are")
        #expect(info[MPMediaItemPropertyArtist] as? String == "Severance")
        #expect(info[MPMediaItemPropertyAlbumTitle] as? String == "Season 1")
        #expect((info[MPMediaItemPropertyPlaybackDuration] as? NSNumber)?.doubleValue == 2_400)
        #expect((info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? NSNumber)?.doubleValue == 125.5)
        #expect((info[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue == 1.5)
        #expect((info[MPNowPlayingInfoPropertyDefaultPlaybackRate] as? NSNumber)?.doubleValue == 1.5)
        #expect(info[MPMediaItemPropertyGenre] as? String == "Drama, Science Fiction")
        #expect(
            info[MPNowPlayingInfoPropertyExternalContentIdentifier] as? String
                == "plex:8:server-a:10:episode-42"
        )
        #expect(
            info[MPNowPlayingInfoCollectionIdentifier] as? String
                == "plex:8:server-a:6:show-7"
        )
        #expect((info[MPNowPlayingInfoPropertyPlaybackQueueIndex] as? NSNumber)?.intValue == 2)
        #expect((info[MPNowPlayingInfoPropertyPlaybackQueueCount] as? NSNumber)?.intValue == 10)
        #expect(
            (info[MPNowPlayingInfoPropertyMediaType] as? NSNumber)?.uintValue
                == MPNowPlayingInfoMediaType.video.rawValue
        )
        #expect((info[MPMediaItemPropertyMediaType] as? NSNumber)?.uintValue == MPMediaType.tvShow.rawValue)
    }

    @Test func serverCreditsMarkerPublishesTheSystemCreditsStartTime() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "movie-42",
          "title": "Movie",
          "type": "movie",
          "Marker": [
            {"type":"intro","startTimeOffset":10000,"endTimeOffset":20000},
            {"type":"credits","startTimeOffset":2300000,"endTimeOffset":2400000}
          ]
        }
        """#)

        let metadata = PlexNowPlayingMetadata(
            item: item,
            duration: 2_400,
            elapsedTime: 0,
            playbackRate: 1
        )

        #expect(metadata.creditsStartTime == 2_300)
        #expect(
            (metadata.nowPlayingInfo[MPNowPlayingInfoPropertyCreditsStartTime] as? NSNumber)?.doubleValue
                == 2_300
        )
    }

    @Test func artworkRequestsPreferHierarchyPostersWithoutLeakingTheTokenIntoURLs() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "episode-42",
          "title": "The We We Are",
          "type": "episode",
          "thumb": "/library/metadata/42/thumb",
          "parentThumb": "/library/metadata/season-1/thumb",
          "grandparentThumb": "/library/metadata/show-1/thumb",
          "art": "/library/metadata/show-1/art"
        }
        """#)
        let serverURL = try #require(URL(string: "https://plex.example.test:32400"))
        let request = try #require(PlexNowPlayingArtworkRequest(
            item: item,
            serverURL: serverURL,
            token: "secret-pms-token",
            clientContext: PlexClientContext(clientIdentifier: "now-playing-artwork-test")
        ))

        #expect(request.candidateURLs.map(\.path) == [
            "/library/metadata/show-1/thumb",
            "/library/metadata/season-1/thumb",
        ])
        #expect(request.candidateURLs.allSatisfy {
            !$0.absoluteString.contains("secret-pms-token")
                && URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.contains {
                    $0.name.caseInsensitiveCompare("X-Plex-Token") == .orderedSame
                } != true
        })
        #expect(request.token == "secret-pms-token")
        #expect(PlexNowPlayingArtworkRequest.maximumPixelSize == 1_200)
    }

    @Test func nowPlayingArtworkUsesTheModernSizeRequestContract() throws {
        let image = try #require(testCGImage(width: 600, height: 900))
        let artwork = PlexNowPlayingArtworkFactory.make(from: image)

        #expect(artwork.bounds.size == CGSize(width: 600, height: 900))
        #expect(artwork.image(at: CGSize(width: 200, height: 300))?.size == CGSize(
            width: 200,
            height: 300
        ))
        #expect(artwork.image(at: CGSize(width: 1_200, height: 1_800))?.size == CGSize(
            width: 600,
            height: 900
        ))

        let item = try decodeItem(#"""
        {"ratingKey":"movie-1","title":"Movie","type":"movie"}
        """#)
        let metadata = PlexNowPlayingMetadata(
            item: item,
            duration: 90,
            elapsedTime: 0,
            playbackRate: 0
        )
        #expect(metadata.nowPlayingInfo[MPMediaItemPropertyArtwork] == nil)
        #expect(metadata.nowPlayingInfo(artwork: artwork)[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork === artwork)
    }

    @MainActor
    @Test func artworkLoaderRejectsAResultSupersededByTheNextItem() async throws {
        let firstImage = try #require(testCGImage(width: 300, height: 450))
        let secondImage = try #require(testCGImage(width: 400, height: 600))
        let gate = NowPlayingArtworkLoadGate(
            delayedRatingKey: "first",
            delayedImage: firstImage,
            immediateImage: secondImage
        )
        let loader = PlexNowPlayingArtworkLoader(fetchImage: { request in
            await gate.fetch(request)
        })
        let serverURL = try #require(URL(string: "https://plex.example.test:32400"))
        let context = PlexClientContext(clientIdentifier: "now-playing-supersession-test")
        let firstRequest = try #require(PlexNowPlayingArtworkRequest(
            item: decodeItem(#"""
            {"ratingKey":"first","title":"First","type":"movie","thumb":"/first"}
            """#),
            serverURL: serverURL,
            token: "",
            clientContext: context
        ))
        let secondRequest = try #require(PlexNowPlayingArtworkRequest(
            item: decodeItem(#"""
            {"ratingKey":"second","title":"Second","type":"movie","thumb":"/second"}
            """#),
            serverURL: serverURL,
            token: "",
            clientContext: context
        ))

        let firstLoad = Task {
            await loader.load(firstRequest)
        }
        await gate.waitUntilDelayedLoadStarts()
        let resolvedSecond = await loader.load(secondRequest)
        await gate.finishDelayedLoad()
        let resolvedFirst = await firstLoad.value

        #expect(resolvedSecond?.width == secondImage.width)
        #expect(resolvedFirst == nil)
    }

    @Test func trackUsesAudioMediaTypeAndClampsInvalidTiming() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "track-9",
          "title": "Kitchen Confidential",
          "type": "track",
          "grandparentTitle": "Anthony Bourdain",
          "parentTitle": "Kitchen Confidential",
          "parentRatingKey": "album-5",
          "index": "9",
          "parentIndex": "2",
          "Genre": [{"tag":"Audiobook"}]
        }
        """#)

        let metadata = PlexNowPlayingMetadata(
            item: item,
            duration: -.infinity,
            elapsedTime: -.infinity,
            playbackRate: -.infinity,
            defaultPlaybackRate: .infinity,
            serverIdentifier: "server-a"
        )

        #expect(metadata.mediaKind == .audio)
        #expect(metadata.duration == nil)
        #expect(metadata.elapsedTime == 0)
        #expect(metadata.playbackRate == 0)
        #expect(metadata.defaultPlaybackRate == 1)
        #expect(metadata.albumTrackNumber == 9)
        #expect(metadata.discNumber == 2)
        #expect(metadata.genre == "Audiobook")
        #expect(metadata.collectionIdentifier == "plex:8:server-a:7:album-5")
        #expect(metadata.nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] == nil)
        #expect(
            (metadata.nowPlayingInfo[MPMediaItemPropertyAlbumTrackNumber] as? NSNumber)?.intValue == 9
        )
        #expect(
            (metadata.nowPlayingInfo[MPMediaItemPropertyDiscNumber] as? NSNumber)?.intValue == 2
        )
        #expect(
            (metadata.nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] as? NSNumber)?.uintValue
                == MPNowPlayingInfoMediaType.audio.rawValue
        )
        #expect(
            (metadata.nowPlayingInfo[MPMediaItemPropertyMediaType] as? NSNumber)?.uintValue
                == MPMediaType.anyAudio.rawValue
        )
    }

    @Test func identifiersAndQueueFactsAreOmittedWhenTheirScopeIsNotAuthoritative() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "episode-42",
          "title": "The We We Are",
          "type": "episode",
          "grandparentRatingKey": "show-7",
          "index": "4",
          "parentIndex": "1"
        }
        """#)

        let metadata = PlexNowPlayingMetadata(
            item: item,
            duration: 2_400,
            elapsedTime: 0,
            playbackRate: 0,
            queuePosition: 11,
            queueCount: 10
        )

        #expect(metadata.externalContentIdentifier == nil)
        #expect(metadata.collectionIdentifier == nil)
        #expect(metadata.queueIndex == nil)
        #expect(metadata.queueCount == nil)
        #expect(metadata.albumTrackNumber == nil)
        #expect(metadata.discNumber == nil)
        #expect(metadata.nowPlayingInfo[MPNowPlayingInfoPropertyExternalContentIdentifier] == nil)
        #expect(metadata.nowPlayingInfo[MPNowPlayingInfoCollectionIdentifier] == nil)
        #expect(metadata.nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] == nil)
        #expect(metadata.nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] == nil)
        #expect(metadata.nowPlayingInfo[MPMediaItemPropertyAlbumTrackNumber] == nil)
        #expect(metadata.nowPlayingInfo[MPMediaItemPropertyDiscNumber] == nil)
    }

    @Test func publicationFingerprintIgnoresClockDriftButDetectsQueueChanges() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "episode-42",
          "title": "The We We Are",
          "type": "episode",
          "grandparentRatingKey": "show-7",
          "grandparentTitle": "Severance"
        }
        """#)
        let original = PlexNowPlayingMetadata(
            item: item,
            duration: 2_400,
            elapsedTime: 100,
            playbackRate: 1,
            serverIdentifier: "server-a",
            queuePosition: 3,
            queueCount: 10
        )
        let ordinaryClockDrift = PlexNowPlayingMetadata(
            item: item,
            duration: 2_400,
            elapsedTime: 101,
            playbackRate: 0,
            serverIdentifier: "server-a",
            queuePosition: 3,
            queueCount: 10
        )
        let changedQueue = PlexNowPlayingMetadata(
            item: item,
            duration: 2_400,
            elapsedTime: 101,
            playbackRate: 0,
            serverIdentifier: "server-a",
            queuePosition: 4,
            queueCount: 12
        )

        #expect(original != ordinaryClockDrift)
        #expect(original.publicationFingerprint == ordinaryClockDrift.publicationFingerprint)
        #expect(original.publicationFingerprint != changedQueue.publicationFingerprint)
    }

    @Test func serverFallbackTracksPublishNativeNowPlayingLanguageGroups() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "movie-1",
          "title": "Movie",
          "type": "movie",
          "Media": [{
            "Part": [{
              "id": "700",
              "Stream": [
                {"id":"21","streamType":"2","displayTitle":"English 5.1","languageCode":"eng","selected":"1"},
                {"id":"22","streamType":"2","displayTitle":"French Audio Description","languageCode":"fra","visualImpaired":"1"},
                {"id":"31","streamType":"3","displayTitle":"English SDH","languageCode":"eng","selected":"1","hearingImpaired":"1"},
                {"id":"32","streamType":"3","displayTitle":"Spanish Forced","languageCode":"spa","forced":"1"}
              ]
            }]
          }]
        }
        """#)
        let selection = PlexPlaybackMediaSelection(
            item: item,
            source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0)
        )
        let languageOptions = PlexNowPlayingLanguageOptions(
            selection: selection,
            nativeAvailability: PlexNativeMediaSelectionAvailability(
                hasAudio: false,
                hasSubtitles: false
            )
        )

        #expect(languageOptions.groups.count == 2)
        #expect(languageOptions.currentOptions.map(\.identifier) == [
            "plex-audio-stream:21",
            "plex-subtitle-stream:31",
        ])
        #expect(languageOptions.hasSelectedSubtitle)

        let audioGroup = languageOptions.groups[0]
        #expect(!audioGroup.allowEmptySelection)
        #expect(audioGroup.defaultLanguageOption?.identifier == "plex-audio-stream:21")
        #expect(audioGroup.languageOptions.map(\.identifier) == [
            "plex-audio-stream:21",
            "plex-audio-stream:22",
        ])
        #expect(audioGroup.languageOptions.map(\.languageTag) == ["eng", "fra"])
        #expect(audioGroup.languageOptions[0].languageOptionCharacteristics?.contains(
            MPLanguageOptionCharacteristicIsMainProgramContent
        ) == true)
        #expect(audioGroup.languageOptions[1].languageOptionCharacteristics?.contains(
            MPLanguageOptionCharacteristicDescribesVideo
        ) == true)

        let subtitleGroup = languageOptions.groups[1]
        #expect(subtitleGroup.allowEmptySelection)
        #expect(subtitleGroup.defaultLanguageOption?.identifier == "plex-subtitle-stream:31")
        #expect(subtitleGroup.languageOptions[0].languageOptionCharacteristics?.contains(
            MPLanguageOptionCharacteristicDescribesMusicAndSound
        ) == true)
        #expect(subtitleGroup.languageOptions[1].languageOptionCharacteristics?.contains(
            MPLanguageOptionCharacteristicContainsOnlyForcedSubtitles
        ) == true)

        let metadata = PlexNowPlayingMetadata(
            item: item,
            duration: 90,
            elapsedTime: 0,
            playbackRate: 0
        )
        let info = metadata.nowPlayingInfo(artwork: nil, languageOptions: languageOptions)
        let publishedGroups = info[MPNowPlayingInfoPropertyAvailableLanguageOptions]
            as? [MPNowPlayingInfoLanguageOptionGroup]
        let publishedCurrent = info[MPNowPlayingInfoPropertyCurrentLanguageOptions]
            as? [MPNowPlayingInfoLanguageOption]
        #expect(publishedGroups?.count == 2)
        #expect(publishedCurrent?.map(\.identifier) == languageOptions.currentOptions.map(\.identifier))

        #expect(PlexNowPlayingLanguageSelection(
            languageOption: audioGroup.languageOptions[1]
        ) == .audio(streamID: 22))
        #expect(PlexNowPlayingLanguageSelection(
            languageOption: subtitleGroup.languageOptions[1]
        ) == .subtitle(streamID: 32))
    }

    @Test func assetNativeGroupsRemainExclusivelyOwnedByAVKit() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "movie-1",
          "title": "Movie",
          "Media": [{
            "Part": [{
              "id": "700",
              "Stream": [
                {"id":"21","streamType":"2","languageCode":"eng","selected":"1"},
                {"id":"22","streamType":"2","languageCode":"fra"},
                {"id":"31","streamType":"3","languageCode":"eng"}
              ]
            }]
          }]
        }
        """#)
        let selection = PlexPlaybackMediaSelection(
            item: item,
            source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0)
        )

        let allNative = PlexNowPlayingLanguageOptions(
            selection: selection,
            nativeAvailability: PlexNativeMediaSelectionAvailability(
                hasAudio: true,
                hasSubtitles: true
            )
        )
        #expect(!allNative.hasAvailableOptions)
        #expect(allNative.currentOptions.isEmpty)

        let audioNative = PlexNowPlayingLanguageOptions(
            selection: selection,
            nativeAvailability: PlexNativeMediaSelectionAvailability(
                hasAudio: true,
                hasSubtitles: false
            )
        )
        #expect(audioNative.groups.count == 1)
        #expect(audioNative.groups[0].languageOptions.allSatisfy {
            $0.languageOptionType == .legible
        })

        let inspectionPending = PlexNowPlayingLanguageOptions(
            selection: selection,
            nativeAvailability: nil
        )
        #expect(!inspectionPending.hasAvailableOptions)
    }

    private func decodeItem(_ json: String) throws -> PlexMediaItem {
        try JSONDecoder().decode(PlexMediaItem.self, from: Data(json.utf8))
    }

    private func testCGImage(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

private actor NowPlayingArtworkLoadGate {
    private let delayedRatingKey: String
    private let delayedImage: PlexCGImageBox
    private let immediateImage: PlexCGImageBox
    private var delayedLoadStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var delayedLoadContinuation: CheckedContinuation<Void, Never>?

    init(delayedRatingKey: String, delayedImage: CGImage, immediateImage: CGImage) {
        self.delayedRatingKey = delayedRatingKey
        self.delayedImage = PlexCGImageBox(delayedImage)
        self.immediateImage = PlexCGImageBox(immediateImage)
    }

    func fetch(_ request: PlexNowPlayingArtworkRequest) async -> PlexCGImageBox? {
        guard request.candidateURLs.first?.path == "/\(delayedRatingKey)" else {
            return immediateImage
        }

        delayedLoadStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            delayedLoadContinuation = continuation
        }
        return delayedImage
    }

    func waitUntilDelayedLoadStarts() async {
        guard !delayedLoadStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func finishDelayedLoad() {
        delayedLoadContinuation?.resume()
        delayedLoadContinuation = nil
    }
}
