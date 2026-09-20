@testable import PlexClientKit
import PlexModels
import Foundation
import Testing
@testable import PlexBar

extension PlexMediaRequestTests {
    @Test func audioOnlyPlaybackUsesMusicDecisionEndpointAndNativeProfile() async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, directPlayDecisionData())
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Chapter 3",
          "type": "track",
          "Media": [{
            "container": "mp4",
            "audioCodec": "aac",
            "bitrate": "256",
            "Part": [{"key": "/library/parts/7/chapter.m4b"}]
          }]
        }
        """#)

        let plan = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities
        )

        let request = try #require(capture.request)
        #expect(request.url?.path == "/music/:/transcode/universal/decision")
        let profile = try #require(request.value(forHTTPHeaderField: "X-Plex-Client-Profile-Extra"))
        #expect(profile.contains("type=musicProfile&container=mp4"))
        #expect(profile.contains("audioCodec=aac"))
        #expect(!profile.contains("type=videoProfile"))
        let queryItems = try capturedQueryItems(capture)
        #expect(queryItems.contains { $0.name == "musicBitrate" && $0.value == "256" })
        #expect(!queryItems.contains { $0.name == "videoQuality" })
        #expect(!queryItems.contains { $0.name == "autoAdjustQuality" })
        #expect(!queryItems.contains { $0.name == "audioBoost" })
        #expect(plan.method == .directPlay)
        #expect(plan.mediaKind == .music)
    }

    @Test(arguments: PlexAudioBoost.allCases)
    func videoPlaybackSendsTheExactAudioBoostPercentage(
        audioBoost: PlexAudioBoost
    ) async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, directPlayDecisionData())
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Charade",
          "type": "movie",
          "Media": [{
            "container": "mp4",
            "videoCodec": "h264",
            "audioCodec": "ac3",
            "Part": [{"key": "/library/parts/7/file.mp4"}]
          }]
        }
        """#)

        _ = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities,
            audioBoost: audioBoost
        )

        let queryItems = try capturedQueryItems(capture)
        #expect(queryItems.contains {
            $0.name == "audioBoost" && $0.value == String(audioBoost.rawValue)
        })
    }

    @Test(arguments: [
        (6, true),
        (2, false),
    ])
    func playbackPlanExposesAudioBoostOnlyForAProvenSurroundDownmix(
        sourceChannels: Int,
        expectedSupport: Bool
    ) async throws {
        let session = makeMediaMockSession { request in
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data(#"""
            {
              "MediaContainer": {
                "generalDecisionCode": "1000",
                "Metadata": [{
                  "ratingKey": "42",
                  "title": "Charade",
                  "Media": [{
                    "selected": "1",
                    "Part": [{
                      "selected": "1",
                      "decision": "transcode",
                      "Stream": [
                        { "streamType": "1", "decision": "copy" },
                        { "streamType": "2", "decision": "transcode", "channels": "2" }
                      ]
                    }]
                  }]
                }]
              }
            }
            """#.utf8))
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Charade",
          "type": "movie",
          "Media": [{
            "container": "mp4",
            "videoCodec": "h264",
            "audioCodec": "ac3",
            "Part": [{
              "key": "/library/parts/7/file.mp4",
              "Stream": [{
                "streamType": "2",
                "codec": "ac3",
                "selected": "1",
                "channels": "\#(sourceChannels)"
              }]
            }]
          }]
        }
        """#)

        let plan = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities
        )

        #expect(plan.supportsAudioBoost == expectedSupport)
    }

    @Test(arguments: [
        (PlexMusicQuality.original, "1", "1", "1", "256"),
        (PlexMusicQuality.kbps320, "1", "1", "1", "320"),
        (PlexMusicQuality.kbps128, "0", "0", "0", "128"),
    ])
    func remoteMusicQualityIsAnExactServerEnforcedCeiling(
        quality: PlexMusicQuality,
        expectedDirectPlay: String,
        expectedDirectStream: String,
        expectedDirectStreamAudio: String,
        expectedMusicBitrate: String
    ) async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, directPlayDecisionData())
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Remote Track",
          "type": "track",
          "Media": [{
            "container": "mp4",
            "audioCodec": "aac",
            "bitrate": "256",
            "Part": [{"container": "mp4", "key": "/library/parts/7/track.m4a"}]
          }]
        }
        """#)

        _ = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities,
            musicQuality: quality
        )

        let queryItems = try capturedQueryItems(capture)
        #expect(queryItems.contains {
            $0.name == "directPlay" && $0.value == expectedDirectPlay
        })
        #expect(queryItems.contains {
            $0.name == "directStream" && $0.value == expectedDirectStream
        })
        #expect(queryItems.contains {
            $0.name == "directStreamAudio" && $0.value == expectedDirectStreamAudio
        })
        #expect(queryItems.contains {
            $0.name == "musicBitrate" && $0.value == expectedMusicBitrate
        })
    }

    @Test func musicQualityCeilingOverridesForceDirectPlay() async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, transcodeDecisionData())
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Lossless Remote Track",
          "type": "track",
          "Media": [{
            "container": "mp4",
            "audioCodec": "aac",
            "bitrate": "921",
            "Part": [{
              "container": "mp4",
              "key": "/library/parts/7/track.m4a",
              "Stream": [{"streamType": "2", "codec": "aac", "selected": "1"}]
            }]
          }]
        }
        """#)

        _ = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities,
            musicQuality: .kbps192,
            streamingPolicy: PlexPlaybackStreamingPolicy(
                allowsDirectPlay: true,
                allowsDirectStream: true,
                forceDirectPlay: true
            )
        )

        let queryItems = try capturedQueryItems(capture)
        #expect(queryItems.contains { $0.name == "directPlay" && $0.value == "0" })
        #expect(queryItems.contains { $0.name == "directStreamAudio" && $0.value == "0" })
        #expect(queryItems.contains { $0.name == "musicBitrate" && $0.value == "192" })
    }

    @Test func musicQualityCeilingDoesNotGuessWhenSourceBitrateIsMissing() async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, transcodeDecisionData())
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Unknown Bitrate Track",
          "type": "track",
          "Media": [{
            "container": "mp4",
            "audioCodec": "aac",
            "Part": [{"container": "mp4", "key": "/library/parts/7/track.m4a"}]
          }]
        }
        """#)

        _ = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities,
            musicQuality: .kbps192
        )

        let queryItems = try capturedQueryItems(capture)
        #expect(queryItems.contains { $0.name == "directPlay" && $0.value == "0" })
        #expect(queryItems.contains { $0.name == "directStreamAudio" && $0.value == "0" })
        #expect(queryItems.contains { $0.name == "musicBitrate" && $0.value == "192" })
    }

    @Test func trackWithoutSelectedAudioFactsDoesNotGuessAMusicContract() async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, directPlayDecisionData())
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Unknown Track",
          "type": "track",
          "Media": [{"Part": [{"key": "/library/parts/7/unknown"}]}]
        }
        """#)

        let plan = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities
        )

        let request = try #require(capture.request)
        #expect(request.url?.path == "/video/:/transcode/universal/decision")
        let profile = try #require(request.value(forHTTPHeaderField: "X-Plex-Client-Profile-Extra"))
        #expect(profile.contains("type=videoProfile"))
        #expect(!profile.contains("type=musicProfile"))
        #expect(plan.mediaKind == .video)
    }

    @Test func playbackDecisionUsesTheExplicitMediaVersion() async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, directPlayDecisionData())
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Charade",
          "Media": [
            { "Part": [{ "key": "/library/parts/4/file-720.mp4" }] },
            {
              "videoCodec": "hevc",
              "width": "3840",
              "height": "2160",
              "bitrate": "48720",
              "Part": [{ "key": "/library/parts/7/file-4k.mp4" }]
            }
          ]
        }
        """#)

        _ = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities,
            source: PlexPlaybackSource(mediaIndex: 1, partIndex: 0)
        )

        let queryItems = try capturedQueryItems(capture)
        #expect(queryItems.contains { $0.name == "mediaIndex" && $0.value == "1" })
        #expect(queryItems.contains { $0.name == "partIndex" && $0.value == "0" })
        #expect(queryItems.contains { $0.name == "videoQuality" && $0.value == "99" })
        #expect(queryItems.contains { $0.name == "videoResolution" && $0.value == "3840x2160" })
        #expect(!queryItems.contains { $0.name == "videoBitrate" })
    }

    @Test func originalHEVCRemuxKeepsTheSameUncappedProfileThroughPlaybackStart() async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            ))
            // PMS still calls the container conversion a transcode; the stream
            // decisions establish that video and audio are both copied intact.
            return (response, Data(#"""
            {"MediaContainer": {
              "generalDecisionCode": 1001,
              "Metadata": [{"ratingKey": "42", "title": "HEVC movie", "Media": [{
                "selected": true, "container": "mp4", "videoCodec": "hevc",
                "width": 1920, "height": 1080, "audioCodec": "aac", "audioChannels": 6,
                "Part": [{"selected": true, "decision": "transcode", "Stream": [
                  {"streamType": 1, "codec": "hevc", "decision": "copy"},
                  {"streamType": 2, "codec": "aac", "channels": 6, "decision": "copy"}
                ]}]
              }]}]
            }}
            """#.utf8))
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "42", "title": "HEVC movie", "Media": [{
            "container": "mkv", "videoCodec": "hevc", "width": 1920, "height": 1080,
            "bitrate": 2218, "audioCodec": "aac", "audioChannels": 6,
            "Part": [{"key": "/library/parts/7/file.mkv"}]
          }]
        }
        """#)

        let plan = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities,
            videoQuality: .original
        )

        #expect(plan.method == .directStream)
        #expect(plan.url.path == "/video/:/transcode/universal/start.m3u8")
        let startItems = try #require(URLComponents(
            url: plan.url, resolvingAgainstBaseURL: false
        )?.queryItems)
        for items in [try capturedQueryItems(capture), startItems] {
            #expect(!items.contains { $0.name == "videoBitrate" || $0.name == "maxVideoBitrate" })
            #expect(items.contains { $0.name == "videoResolution" && $0.value == "1920x1080" })
            #expect(items.contains { $0.name == "directStream" && $0.value == "1" })
            #expect(items.contains { $0.name == "directStreamAudio" && $0.value == "1" })
        }
        let decisionProfile = try #require(capture.request?.value(
            forHTTPHeaderField: "X-Plex-Client-Profile-Extra"
        ))
        #expect(decisionProfile.contains(
            "container=mp4&videoCodec=h264,hevc&audioCodec=aac&replace=true"
        ))
        #expect(startItems.first { $0.name == "X-Plex-Client-Profile-Extra" }?.value == decisionProfile)
    }

    @Test func multipartVersionAsksPlexToJoinItsParts() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Charade",
          "Media": [{
            "selected": "1",
            "Part": [
              { "key": "/library/parts/7/disc-1.mp4" },
              { "key": "/library/parts/8/disc-2.mp4" }
            ]
          }]
        }
        """#)

        #expect(item.defaultPlaybackSource == PlexPlaybackSource(mediaIndex: 0, partIndex: -1))
    }

    @Test func playbackDecisionRejectsAnInvalidSourceBeforeRequestingPlex() async throws {
        let session = makeMediaMockSession { _ in
            Issue.record("Invalid source should not make a request")
            throw URLError(.badServerResponse)
        }
        let item = try JSONDecoder().decode(PlexMediaItem.self, from: playableItemData())

        await #expect(throws: PlexAPIError.self) {
            try await PlexAPIClient(session: session).makePlaybackPlan(
                for: item,
                using: try playbackConfiguration,
                capabilities: capabilities,
                source: PlexPlaybackSource(mediaIndex: 8, partIndex: 0)
            )
        }
    }

    @Test func limitedVideoQualityForcesTheRequestedTranscodeLimits() async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, transcodeDecisionData())
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Charade",
          "Media": [{
            "videoCodec": "hevc",
            "width": "3840",
            "height": "2160",
            "bitrate": "48720",
            "Part": [{ "key": "/library/parts/7/file-4k.mp4" }]
          }]
        }
        """#)

        _ = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities,
            videoQuality: .fullHD8Mbps
        )

        let queryItems = try capturedQueryItems(capture)
        #expect(queryItems.contains { $0.name == "directPlay" && $0.value == "0" })
        #expect(queryItems.contains { $0.name == "directStream" && $0.value == "0" })
        #expect(queryItems.contains { $0.name == "videoResolution" && $0.value == "1920x1080" })
        #expect(queryItems.contains { $0.name == "videoBitrate" && $0.value == "8000" })
    }

    @Test func qualityCeilingKeepsASourceWithinItsLimitsEligibleForDirectPlay() async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, directPlayDecisionData())
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Already Small Enough",
          "Media": [{
            "videoCodec": "h264",
            "width": "1280",
            "height": "720",
            "bitrate": "3500",
            "Part": [{"key": "/library/parts/7/file.mp4"}]
          }]
        }
        """#)

        _ = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities,
            videoQuality: .fullHD8Mbps
        )

        let queryItems = try capturedQueryItems(capture)
        #expect(queryItems.contains { $0.name == "directPlay" && $0.value == "1" })
        #expect(queryItems.contains { $0.name == "directStream" && $0.value == "1" })
    }

    @Test(arguments: [
        (PlexVideoQuality.fullHD8Mbps, false, "0", "0", "0"),
        (PlexVideoQuality.fullHD8Mbps, true, "1", "1", "1"),
        (PlexVideoQuality.original, false, "1", "1", "1"),
    ])
    func smallerVideoOriginalQualityPolicyControlsAdaptiveConversion(
        quality: PlexVideoQuality,
        playsSmallerAtOriginal: Bool,
        expectedDirectPlay: String,
        expectedDirectStream: String,
        expectedDirectStreamAudio: String
    ) async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, transcodeDecisionData())
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Already Small Enough",
          "type": "movie",
          "Media": [{
            "videoCodec": "h264",
            "width": "1280",
            "height": "720",
            "bitrate": "3500",
            "Part": [{"key": "/library/parts/7/file.mp4"}]
          }]
        }
        """#)

        _ = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities,
            videoQuality: quality,
            automaticallyAdjustVideoQuality: true,
            playSmallerVideosAtOriginalQuality: playsSmallerAtOriginal
        )

        let queryItems = try capturedQueryItems(capture)
        #expect(queryItems.contains {
            $0.name == "directPlay" && $0.value == expectedDirectPlay
        })
        #expect(queryItems.contains {
            $0.name == "directStream" && $0.value == expectedDirectStream
        })
        #expect(queryItems.contains {
            $0.name == "directStreamAudio" && $0.value == expectedDirectStreamAudio
        })
    }

    @Test func qualityCeilingRequiresServerEnforcementWhenSourceFactsAreIncomplete() async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, transcodeDecisionData())
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Unknown Source Size",
          "Media": [{
            "videoCodec": "h264",
            "Part": [{"key": "/library/parts/7/file.mp4"}]
          }]
        }
        """#)

        _ = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities,
            videoQuality: .hd4Mbps
        )

        let queryItems = try capturedQueryItems(capture)
        #expect(queryItems.contains { $0.name == "directPlay" && $0.value == "0" })
        #expect(queryItems.contains { $0.name == "directStream" && $0.value == "0" })
    }

    @Test func playbackDecisionPreservesSubsecondReloadPosition() async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, directPlayDecisionData())
        }
        let item = try JSONDecoder().decode(PlexMediaItem.self, from: playableItemData())

        _ = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities,
            startTimeOverride: 123.4567
        )

        #expect(try capturedQueryItems(capture).contains {
            $0.name == "offset" && $0.value == "123.457"
        })
    }

    @Test func explicitStartTimeOverridesAStoredResumeOffset() async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, directPlayDecisionData())
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Previously Watched Episode",
          "type": "episode",
          "viewOffset": "3599000",
          "Media": [{"Part": [{"key": "/library/parts/7/file.mp4"}]}]
        }
        """#)

        let plan = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities,
            startTimeOverride: 0
        )

        #expect(plan.startTime == 0)
        #expect(try capturedQueryItems(capture).contains { $0.name == "offset" && $0.value == "0" })
    }

    @Test func playbackStartOptionsKeepResumeServerOwnedAndBeginningExplicit() {
        #expect(PlexPlaybackStartOption.resume.startTimeOverride == nil)
        #expect(PlexPlaybackStartOption.beginning.startTimeOverride == 0)
    }

    @Test func cinemaPreplayAppliesOnlyToFreshMovieStarts() throws {
        let movie = try decodeItem(#"{"ratingKey":"42","key":"/library/metadata/42","title":"Feature","type":"movie","Media":[]}"#)
        let episode = try decodeItem(#"{"ratingKey":"43","key":"/library/metadata/43","title":"Episode","type":"episode","Media":[]}"#)

        #expect(PlexCinemaPreplayRequestPolicy.extrasPrefixCount(
            for: movie,
            startOption: .beginning,
            preference: .off
        ) == nil)
        #expect(PlexCinemaPreplayRequestPolicy.extrasPrefixCount(
            for: movie,
            startOption: .beginning,
            preference: .preRollOnly
        ) == 0)
        #expect(PlexCinemaPreplayRequestPolicy.extrasPrefixCount(
            for: movie,
            startOption: .beginning,
            preference: .fiveTrailers
        ) == 5)
        #expect(PlexCinemaPreplayRequestPolicy.extrasPrefixCount(
            for: movie,
            startOption: .resume,
            preference: .fiveTrailers
        ) == nil)
        #expect(PlexCinemaPreplayRequestPolicy.extrasPrefixCount(
            for: episode,
            startOption: .beginning,
            preference: .fiveTrailers
        ) == nil)
    }

    @Test func cinemaQueueSourcePreferenceTargetsOnlyTheRequestedMovie() throws {
        let movie = try decodeItem(#"{"ratingKey":"42","title":"Feature","type":"movie","Media":[]}"#)
        let trailer = try decodeItem(#"{"ratingKey":"700","title":"Trailer","type":"clip","Media":[]}"#)
        let source = PlexPlaybackSource(mediaIndex: 2, partIndex: 0)
        let preference = PlexPlaybackQueueSourcePreference(
            ratingKey: movie.ratingKey,
            source: source
        )

        #expect(preference.source(for: movie) == source)
        #expect(preference.source(for: trailer) == nil)
    }

    @Test func resumeRequiresAPositiveServerOffset() throws {
        let withoutOffset = try decodeItem(#"""
        {
          "ratingKey": "40",
          "title": "Unstarted",
          "Media": []
        }
        """#)
        let zeroOffset = try decodeItem(#"""
        {
          "ratingKey": "41",
          "title": "At Beginning",
          "viewOffset": "0",
          "Media": []
        }
        """#)
        let positiveOffset = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "In Progress",
          "viewOffset": "12500",
          "Media": []
        }
        """#)

        #expect(!withoutOffset.hasResumePosition)
        #expect(!zeroOffset.hasResumePosition)
        #expect(positiveOffset.hasResumePosition)
    }

    @Test func explicitServerMediaSelectionDisablesDirectPlayButKeepsDirectStreamAvailable() async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, transcodeDecisionData())
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Alternate Audio",
          "Media": [{
            "videoCodec": "h264",
            "width": "1920",
            "height": "1080",
            "bitrate": "8000",
            "Part": [{"key": "/library/parts/7/file.mp4"}]
          }]
        }
        """#)

        let plan = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities,
            forceServerMediaSelection: true
        )

        let queryItems = try capturedQueryItems(capture)
        #expect(queryItems.contains { $0.name == "directPlay" && $0.value == "0" })
        #expect(queryItems.contains { $0.name == "directStream" && $0.value == "1" })
        #expect(plan.usesServerMediaSelection)
    }

    @Test(arguments: [
        (PlexPlaybackStreamingPolicy(allowsDirectPlay: false, allowsDirectStream: true), "0", "1", "1"),
        (PlexPlaybackStreamingPolicy(allowsDirectPlay: true, allowsDirectStream: false), "1", "0", "0"),
        (PlexPlaybackStreamingPolicy(allowsDirectPlay: false, allowsDirectStream: false), "0", "0", "0"),
    ])
    func streamingPolicyMapsExactlyToPlexDecisionFlags(
        policy: PlexPlaybackStreamingPolicy,
        expectedDirectPlay: String,
        expectedDirectStream: String,
        expectedDirectStreamAudio: String
    ) async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, transcodeDecisionData())
        }
        let item = try JSONDecoder().decode(PlexMediaItem.self, from: playableItemData())

        _ = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities,
            streamingPolicy: policy
        )

        let queryItems = try capturedQueryItems(capture)
        #expect(queryItems.contains { $0.name == "directPlay" && $0.value == expectedDirectPlay })
        #expect(queryItems.contains { $0.name == "directStream" && $0.value == expectedDirectStream })
        #expect(queryItems.contains {
            $0.name == "directStreamAudio" && $0.value == expectedDirectStreamAudio
        })
    }

    @Test(arguments: [
        (PlexSubtitleBurnMode.automatic, "auto", "burn"),
        (PlexSubtitleBurnMode.always, "burn", "burn"),
        (PlexSubtitleBurnMode.imageFormatsOnly, "auto", "text"),
    ])
    func subtitleBurnModeMapsExactlyToPlexDecisionParameters(
        mode: PlexSubtitleBurnMode,
        expectedSubtitles: String,
        expectedAdvancedSubtitles: String
    ) async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, transcodeDecisionData())
        }
        let item = try JSONDecoder().decode(PlexMediaItem.self, from: playableItemData())

        _ = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities,
            subtitleBurnMode: mode
        )

        let queryItems = try capturedQueryItems(capture)
        #expect(queryItems.contains {
            $0.name == "subtitles" && $0.value == expectedSubtitles
        })
        #expect(queryItems.contains {
            $0.name == "advancedSubtitles" && $0.value == expectedAdvancedSubtitles
        })
    }

    @Test(arguments: PlexSubtitleSize.allCases)
    func subtitleSizeMapsToPlexDecisionPercentage(
        size: PlexSubtitleSize
    ) async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, transcodeDecisionData())
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Sized Subtitles",
          "type": "movie",
          "Media": [{
            "container": "mp4",
            "videoCodec": "h264",
            "audioCodec": "aac",
            "Part": [{"id": "700", "key": "/library/parts/700/file.mp4"}]
          }]
        }
        """#)

        _ = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities,
            subtitleSize: size
        )

        #expect(try capturedQueryItems(capture).contains {
            $0.name == "subtitleSize" && $0.value == String(size.rawValue)
        })
    }

    @Test(arguments: [
        (true, true, "1"),
        (true, false, "0"),
        (false, true, "0"),
    ])
    func subtitleAutoSyncRequiresBothUserPreferenceAndStreamCapability(
        isEnabled: Bool,
        canAutoSync: Bool,
        expectedValue: String
    ) async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, transcodeDecisionData())
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Subtitle Sync",
          "type": "movie",
          "Media": [{
            "container": "mp4",
            "videoCodec": "h264",
            "audioCodec": "aac",
            "Part": [{
              "id": "700",
              "key": "/library/parts/700/file.mp4",
              "Stream": [{
                "id": "31",
                "streamType": "3",
                "codec": "srt",
                "selected": "1",
                "canAutoSync": ":canAutoSync"
              }]
            }]
          }]
        }
        """#.replacing(":canAutoSync", with: canAutoSync ? "1" : "0"))

        let plan = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities,
            automaticallySyncSubtitles: isEnabled
        )

        let queryItems = try capturedQueryItems(capture)
        #expect(queryItems.contains {
            $0.name == "autoAdjustSubtitle" && $0.value == expectedValue
        })
        #expect(plan.supportsSubtitleAutoSync == canAutoSync)
    }

    @Test func musicDecisionOmitsVideoSubtitleParameters() async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, transcodeDecisionData())
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "track",
          "title": "Track",
          "type": "track",
          "Media": [{
            "container": "flac",
            "audioCodec": "flac",
            "Part": [{"id": "701", "key": "/library/parts/701/file.flac"}]
          }]
        }
        """#)

        _ = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities
        )

        #expect(try !capturedQueryItems(capture).contains {
            $0.name == "autoAdjustSubtitle"
        })
        #expect(try !capturedQueryItems(capture).contains {
            $0.name == "subtitleSize"
        })
    }

    @Test(arguments: [
        (false, "0"),
        (true, "1"),
    ])
    func automaticQualityMapsExactlyToPlexDecisionFlag(
        isEnabled: Bool,
        expectedValue: String
    ) async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, transcodeDecisionData())
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Adaptive Movie",
          "type": "movie",
          "Media": [{
            "videoCodec": "h264",
            "width": "1920",
            "height": "1080",
            "bitrate": "8000",
            "Part": [{"key": "/library/parts/7/file.mp4"}]
          }]
        }
        """#)

        _ = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities,
            automaticallyAdjustVideoQuality: isEnabled
        )

        let queryItems = try capturedQueryItems(capture)
        #expect(queryItems.contains {
            $0.name == "autoAdjustQuality" && $0.value == expectedValue
        })
    }

    @Test func forcedAdaptiveConversionDisablesEveryOriginalVideoPath() async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, transcodeDecisionData())
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Convert This Movie",
          "type": "movie",
          "Media": [{
            "container": "mp4",
            "videoCodec": "h264",
            "audioCodec": "aac",
            "width": "1920",
            "height": "1080",
            "bitrate": "8000",
            "Part": [{
              "container": "mp4",
              "key": "/library/parts/7/file.mp4",
              "Stream": [
                {"streamType": "1", "codec": "h264", "selected": "1"},
                {"streamType": "2", "codec": "aac", "selected": "1"}
              ]
            }]
          }]
        }
        """#)

        _ = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities,
            streamingPolicy: PlexPlaybackStreamingPolicy(
                allowsDirectPlay: true,
                allowsDirectStream: true,
                forceDirectPlay: true
            ),
            automaticallyAdjustVideoQuality: true,
            forceVideoTranscode: true
        )

        let queryItems = try capturedQueryItems(capture)
        #expect(queryItems.contains { $0.name == "directPlay" && $0.value == "0" })
        #expect(queryItems.contains { $0.name == "directStream" && $0.value == "0" })
        #expect(queryItems.contains { $0.name == "directStreamAudio" && $0.value == "0" })
        #expect(queryItems.contains { $0.name == "autoAdjustQuality" && $0.value == "1" })
    }

    @Test func forcedVideoConversionDoesNotChangeMusicDecisions() async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, directPlayDecisionData())
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Keep This Track Original",
          "type": "track",
          "Media": [{
            "container": "mp4",
            "audioCodec": "aac",
            "bitrate": "256",
            "Part": [{"key": "/library/parts/7/track.m4a"}]
          }]
        }
        """#)

        _ = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities,
            automaticallyAdjustVideoQuality: true,
            forceVideoTranscode: true
        )

        let queryItems = try capturedQueryItems(capture)
        #expect(queryItems.contains { $0.name == "directPlay" && $0.value == "1" })
        #expect(queryItems.contains { $0.name == "directStream" && $0.value == "1" })
        #expect(queryItems.contains { $0.name == "directStreamAudio" && $0.value == "1" })
        #expect(!queryItems.contains { $0.name == "autoAdjustQuality" })
    }

    @Test func forceDirectPlayUsesAnExactNativeSinglePartWithoutRequestingADecision() async throws {
        let session = makeMediaMockSession { _ in
            Issue.record("A native-safe forced direct play must not request a PMS decision")
            throw URLError(.badServerResponse)
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Native File",
          "type": "movie",
          "duration": "5400000",
          "Media": [{
            "container": "mp4",
            "videoCodec": "h264",
            "audioCodec": "aac",
            "Part": [{
              "container": "mp4",
              "key": "/library/parts/7/native-file.mp4",
              "Stream": [
                {"streamType": "1", "codec": "h264", "selected": "1"},
                {"streamType": "2", "codec": "aac", "selected": "1"}
              ]
            }]
          }]
        }
        """#)

        let plan = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities,
            streamingPolicy: PlexPlaybackStreamingPolicy(
                allowsDirectPlay: true,
                allowsDirectStream: true,
                forceDirectPlay: true
            )
        )

        let components = try #require(URLComponents(url: plan.url, resolvingAgainstBaseURL: false))
        #expect(plan.method == .directPlay)
        #expect(plan.source == PlexPlaybackSource(mediaIndex: 0, partIndex: 0))
        #expect(components.path == "/library/parts/7/native-file.mp4")
        #expect(components.queryItems?.contains { $0.name == "X-Plex-Token" && $0.value == "server-token" } == true)
        #expect(components.queryItems?.contains { $0.name == "X-Plex-Session-Identifier" } == true)
        #expect(components.queryItems?.contains { $0.name == "directPlay" } == false)
    }

    @Test func forceDirectPlayUsesAnExactNativeMusicPair() async throws {
        let session = makeMediaMockSession { _ in
            Issue.record("A native-safe music file must not request a PMS decision")
            throw URLError(.badServerResponse)
        }
        let item = try decodeItem(#"""
        {
          "ratingKey": "track-42",
          "title": "Native Track",
          "type": "track",
          "Media": [{
            "container": "mp3",
            "audioCodec": "mp3",
            "Part": [{
              "key": "/library/parts/8/native-track.mp3",
              "Stream": [{"streamType": "2", "codec": "mp3", "selected": "1"}]
            }]
          }]
        }
        """#)

        let plan = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities,
            streamingPolicy: PlexPlaybackStreamingPolicy(
                allowsDirectPlay: true,
                allowsDirectStream: true,
                forceDirectPlay: true
            )
        )

        #expect(plan.method == .directPlay)
        #expect(plan.mediaKind == .music)
        #expect(plan.url.path == "/library/parts/8/native-track.mp3")
    }

    @Test func forceDirectPlayFallsBackToPMSWhenTheNativeContractIsNotProven() async throws {
        let unsafeItems = try [
            decodeItem(#"""
            {
              "ratingKey": "mkv",
              "title": "Unsupported Container",
              "type": "movie",
              "Media": [{
                "container": "mkv",
                "videoCodec": "h264",
                "audioCodec": "aac",
                "Part": [{"key": "/library/parts/1/file.mkv"}]
              }]
            }
            """#),
            decodeItem(#"""
            {
              "ratingKey": "missing-facts",
              "title": "Missing Codec Facts",
              "type": "movie",
              "Media": [{
                "container": "mp4",
                "Part": [{"key": "/library/parts/2/file.mp4"}]
              }]
            }
            """#),
            decodeItem(#"""
            {
              "ratingKey": "multipart",
              "title": "Multipart Movie",
              "type": "movie",
              "Media": [{
                "container": "mp4",
                "videoCodec": "h264",
                "audioCodec": "aac",
                "Part": [
                  {"key": "/library/parts/3/disc-1.mp4"},
                  {"key": "/library/parts/4/disc-2.mp4"}
                ]
              }]
            }
            """#),
            decodeItem(#"""
            {
              "ratingKey": "subtitle",
              "title": "Selected Subtitle",
              "type": "movie",
              "Media": [{
                "container": "mp4",
                "videoCodec": "h264",
                "audioCodec": "aac",
                "Part": [{
                  "key": "/library/parts/5/file.mp4",
                  "Stream": [{
                    "streamType": "3",
                    "codec": "ass",
                    "selected": "1"
                  }]
                }]
              }]
            }
            """#),
        ]

        for item in unsafeItems {
            let source = try #require(item.defaultPlaybackSource)
            #expect(capabilities.directPlayPath(for: item, source: source) == nil)
        }
    }

    @Test func forceDirectPlayDefersToQualityAndExplicitStreamSelection() async throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Large Native File",
          "type": "movie",
          "Media": [{
            "container": "mp4",
            "videoCodec": "h264",
            "audioCodec": "aac",
            "width": "3840",
            "height": "2160",
            "bitrate": "48000",
            "Part": [{"key": "/library/parts/7/file.mp4"}]
          }]
        }
        """#)
        let policy = PlexPlaybackStreamingPolicy(
            allowsDirectPlay: true,
            allowsDirectStream: true,
            forceDirectPlay: true
        )

        for requestContract in [
            (PlexVideoQuality.fullHD8Mbps, false),
            (PlexVideoQuality.original, true),
        ] {
            let capture = RequestCapture()
            let session = makeMediaMockSession { request in
                capture.record(request)
                let response = try #require(HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                ))
                return (response, transcodeDecisionData())
            }

            _ = try await PlexAPIClient(session: session).makePlaybackPlan(
                for: item,
                using: try playbackConfiguration,
                capabilities: capabilities,
                videoQuality: requestContract.0,
                streamingPolicy: policy,
                forceServerMediaSelection: requestContract.1
            )

            let request = try #require(capture.request)
            let queryItems = try capturedQueryItems(capture)
            #expect(request.url?.path == "/video/:/transcode/universal/decision")
            #expect(queryItems.contains { $0.name == "directPlay" && $0.value == "0" })
        }
    }

    @Test func disablingDirectPlayTakesPrecedenceOverForceDirectPlay() async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, transcodeDecisionData())
        }
        let item = try JSONDecoder().decode(PlexMediaItem.self, from: playableItemData())

        _ = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try playbackConfiguration,
            capabilities: capabilities,
            streamingPolicy: PlexPlaybackStreamingPolicy(
                allowsDirectPlay: false,
                allowsDirectStream: true,
                forceDirectPlay: true
            )
        )

        #expect(try capturedQueryItems(capture).contains {
            $0.name == "directPlay" && $0.value == "0"
        })
    }

    @Test func streamSelectionUsesTheDocumentedPartEndpoint() async throws {
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data())
        }

        try await PlexAPIClient(session: session).selectMediaStreams(
            partID: 700,
            audioStreamID: 21,
            subtitleStreamID: 33,
            allParts: true,
            using: try playbackConfiguration
        )

        let request = try #require(capture.request)
        let components = try #require(
            request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        )
        #expect(request.httpMethod == "PUT")
        #expect(components.path == "/library/parts/700")
        #expect(components.queryItems?.contains { $0.name == "audioStreamID" && $0.value == "21" } == true)
        #expect(components.queryItems?.contains { $0.name == "subtitleStreamID" && $0.value == "33" } == true)
        #expect(components.queryItems?.contains { $0.name == "allParts" && $0.value == "1" } == true)
    }

    private var playbackConfiguration: PlexConnectionConfiguration {
        get throws {
            PlexConnectionConfiguration(
                serverURL: try #require(PlexURLBuilder.normalizeServerURL("https://plex.local:32400")),
                token: "server-token",
                clientContext: PlexClientContext(clientIdentifier: "client-123")
            )
        }
    }

    private var capabilities: PlexPlaybackCapabilities {
        PlexPlaybackCapabilities(
            directPlayContainers: ["mp4"],
            directPlayVideoCodecs: ["h264", "hevc"],
            directPlayAudioCodecs: ["aac"],
            directPlayMusicProfiles: [
                PlexMusicDirectPlayProfile(container: "mp3", audioCodec: "mp3"),
                PlexMusicDirectPlayProfile(container: "mp4", audioCodec: "aac"),
            ]
        )
    }

    private func decodeItem(_ json: String) throws -> PlexMediaItem {
        try JSONDecoder().decode(PlexMediaItem.self, from: Data(json.utf8))
    }

    private func capturedQueryItems(_ capture: RequestCapture) throws -> [URLQueryItem] {
        let request = try #require(capture.request)
        let components = try #require(
            request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        )
        return components.queryItems ?? []
    }
}
