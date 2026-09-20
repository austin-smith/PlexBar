@testable import PlexClientKit
import Foundation
import Testing
@testable import PlexBar

struct PlexPlaybackDecisionResolverTests {
    @Test func selectsTheExactDirectPlayPartReturnedByPlex() throws {
        let decision = try decodeDecision(directPlayDecisionData())

        #expect(PlexPlaybackDecisionResolver.resolve(decision, mediaKind: .video) == .selected(
            PlexPlaybackSelection(method: .directPlay, path: "/library/parts/7/file.mp4")
        ))
    }

    @Test func mapsTranscodedVideoToTheNativeHLSStartEndpoint() throws {
        let decision = try decodeDecision(transcodeDecisionData())

        #expect(PlexPlaybackDecisionResolver.resolve(decision, mediaKind: .video) == .selected(
            PlexPlaybackSelection(method: .transcode, path: "/video/:/transcode/universal/start.m3u8")
        ))
    }

    @Test func mapsCopiedStreamsToTheNativeHLSStartEndpoint() throws {
        let decision = try decodeDecision(Data(#"""
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
                  "decision": "copy",
                  "Stream": [{ "streamType": "1", "decision": "copy" }]
                }]
              }]
            }]
          }
        }
        """#.utf8))

        #expect(PlexPlaybackDecisionResolver.resolve(decision, mediaKind: .video) == .selected(
            PlexPlaybackSelection(
                method: .directStream,
                path: "/video/:/transcode/universal/start.m3u8"
            )
        ))
    }

    @Test func exposesAudioBoostOnlyForTranscodedStereoOutput() throws {
        let decision = try decodeDecision(Data(#"""
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

        #expect(PlexPlaybackDecisionResolver.resolve(decision, mediaKind: .video) == .selected(
            PlexPlaybackSelection(
                method: .transcode,
                path: "/video/:/transcode/universal/start.m3u8",
                supportsAudioBoost: true
            )
        ))
    }

    @Test(arguments: [
        (6, "transcode"),
        (2, "copy"),
    ])
    func hidesAudioBoostWhenOutputIsNotStereoOrAudioIsNotTranscoded(
        channels: Int,
        audioDecision: String
    ) throws {
        let decision = try decodeDecision(Data(#"""
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
                    { "streamType": "1", "decision": "transcode" },
                    {
                      "streamType": "2",
                      "decision": "\#(audioDecision)",
                      "channels": "\#(channels)"
                    }
                  ]
                }]
              }]
            }]
          }
        }
        """#.utf8))

        let resolution = PlexPlaybackDecisionResolver.resolve(decision, mediaKind: .video)
        guard case .selected(let selection) = resolution else {
            Issue.record("Expected a playable selection")
            return
        }
        #expect(!selection.supportsAudioBoost)
    }

    @Test func preservesTheServerPlaybackRejectionReason() throws {
        let decision = try decodeDecision(Data(#"""
        {
          "MediaContainer": {
            "generalDecisionCode": "2000",
            "generalDecisionText": "Playback is not possible for this item."
          }
        }
        """#.utf8))

        #expect(PlexPlaybackDecisionResolver.resolve(decision, mediaKind: .video) == .rejected(
            "Playback is not possible for this item."
        ))
    }

    @Test func reportsMissingPlayableMediaWhenTheDecisionHasNoPart() throws {
        let decision = try decodeDecision(Data(#"""
        {
          "MediaContainer": {
            "generalDecisionCode": "1000",
            "Metadata": []
          }
        }
        """#.utf8))

        #expect(PlexPlaybackDecisionResolver.resolve(decision, mediaKind: .video) == .noPlayableMedia)
    }

    private func decodeDecision(_ data: Data) throws -> PlexPlaybackDecisionContainer {
        try JSONDecoder().decode(PlexPlaybackDecisionEnvelope.self, from: data).mediaContainer
    }
}
