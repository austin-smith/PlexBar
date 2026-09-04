import Foundation
import Testing
@testable import PlexBar

struct PlexDownloadPreferencesTests {
    @Test func originalVideoPreservesSourceQualityAndUsesSelectableSubtitles() throws {
        let item = try decodeDownloadItem(#"""
        {
          "ratingKey": "42",
          "key": "/library/metadata/42",
          "title": "Movie",
          "type": "movie",
          "Media": [{
            "videoCodec": "hevc",
            "audioCodec": "aac",
            "width": 3840,
            "height": 2160,
            "bitrate": 18000,
            "Part": [{"key": "/library/parts/7/file.mkv"}]
          }]
        }
        """#)

        let decision = try PlexDownloadPreferences.default.decisionParameters(
            for: item,
            source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0),
            sessionIdentifier: "download-session"
        )

        #expect(decision.mediaPath == "/library/metadata/42")
        #expect(decision.deliveryProtocol == .http)
        #expect(decision.allowsDirectPlay == true)
        #expect(decision.allowsDirectStream == true)
        #expect(decision.allowsDirectStreamAudio == true)
        #expect(decision.videoQuality == 99)
        #expect(decision.videoBitrate == 18_000)
        #expect(decision.videoResolution == "3840x2160")
        #expect(decision.subtitleMode == .embedded)
        #expect(decision.advancedSubtitleMode == .text)
        #expect(decision.musicBitrate == nil)
    }

    @Test func constrainedVideoForcesTheExactDownloadTarget() throws {
        let item = try decodeDownloadItem(Self.fourKVideoJSON)
        let preferences = PlexDownloadPreferences(
            videoQuality: .hd4Mbps,
            musicQuality: .original,
            subtitlePreference: .selectable
        )

        let decision = try preferences.decisionParameters(
            for: item,
            source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0),
            sessionIdentifier: "download-session",
            clientProfileName: "generic",
            clientProfileExtra: "static-profile"
        )

        #expect(decision.allowsDirectPlay == false)
        #expect(decision.allowsDirectStream == false)
        #expect(decision.videoQuality == 99)
        #expect(decision.videoBitrate == 4_000)
        #expect(decision.videoResolution == "1280x720")
        #expect(decision.subtitleMode == .embedded)
        #expect(decision.advancedSubtitleMode == .text)
        #expect(decision.clientProfileName == "generic")
        #expect(decision.clientProfileExtra == "static-profile")
    }

    @Test func subtitleChoicesMapOnlyToDocumentedQueueModes() throws {
        let item = try decodeDownloadItem(Self.fourKVideoJSON)
        let source = PlexPlaybackSource(mediaIndex: 0, partIndex: 0)
        let expected: [
            PlexDownloadSubtitlePreference: (
                PlexDownloadSubtitleMode,
                PlexDownloadAdvancedSubtitleMode?
            )
        ] = [
            .selectable: (.embedded, .text),
            .burn: (.burn, .burn),
            .none: (.none, nil),
        ]

        for preference in PlexDownloadSubtitlePreference.allCases {
            let decision = try PlexDownloadPreferences(
                videoQuality: .original,
                musicQuality: .original,
                subtitlePreference: preference
            ).decisionParameters(
                for: item,
                source: source,
                sessionIdentifier: "download-session"
            )
            #expect(decision.subtitleMode == expected[preference]?.0)
            #expect(decision.advancedSubtitleMode == expected[preference]?.1)
        }
    }

    @Test func musicQualityUsesOnlyTheMusicDecisionContract() throws {
        let item = try decodeDownloadItem(#"""
        {
          "ratingKey": "84",
          "key": "/library/metadata/84",
          "title": "Track",
          "type": "track",
          "Media": [{
            "container": "flac",
            "audioCodec": "flac",
            "bitrate": 900,
            "Part": [{"key": "/library/parts/9/file.flac"}]
          }]
        }
        """#)
        let preferences = PlexDownloadPreferences(
            videoQuality: .sd1500Kbps,
            musicQuality: .kbps192,
            subtitlePreference: .burn
        )

        let decision = try preferences.decisionParameters(
            for: item,
            source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0),
            sessionIdentifier: "music-download"
        )

        #expect(decision.allowsDirectPlay == false)
        #expect(decision.allowsDirectStreamAudio == false)
        #expect(decision.musicBitrate == 192)
        #expect(decision.videoBitrate == nil)
        #expect(decision.videoQuality == nil)
        #expect(decision.videoResolution == nil)
        #expect(decision.subtitleMode == nil)
        #expect(decision.advancedSubtitleMode == nil)
    }

    @Test func multipartVideoUsesPlexJoinIndexAndForcesOneConvertedFile() throws {
        let item = try decodeDownloadItem(#"""
        {
          "ratingKey": "multipart",
          "key": "/library/metadata/multipart",
          "title": "Multipart Movie",
          "type": "movie",
          "Media": [{
            "container": "mkv",
            "videoCodec": "h264",
            "audioCodec": "aac",
            "width": 1920,
            "height": 1080,
            "bitrate": 8000,
            "Part": [
              {"key": "/library/parts/70/first.mkv"},
              {"key": "/library/parts/71/second.mkv"}
            ]
          }]
        }
        """#)

        let decision = try PlexDownloadPreferences.default.decisionParameters(
            for: item,
            source: PlexPlaybackSource(mediaIndex: 0, partIndex: -1),
            sessionIdentifier: "multipart-download"
        )

        #expect(decision.mediaIndex == 0)
        #expect(decision.partIndex == -1)
        #expect(decision.allowsDirectPlay == false)
        #expect(decision.allowsDirectStream == false)
        #expect(decision.allowsDirectStreamAudio == false)
        #expect(decision.deliveryProtocol == .http)
    }

    @Test func invalidOrFactlessSourcesFailClosed() throws {
        let item = try decodeDownloadItem(#"""
        {
          "ratingKey": "42",
          "title": "Unknown",
          "type": "movie",
          "Media": [{"Part": [{"key": "/library/parts/7/file.bin"}]}]
        }
        """#)

        #expect(throws: PlexDownloadPreferencesError.unsupportedMedia) {
            _ = try PlexDownloadPreferences.default.decisionParameters(
                for: item,
                source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0),
                sessionIdentifier: "download-session"
            )
        }
        #expect(throws: PlexDownloadPreferencesError.invalidMediaSource) {
            _ = try PlexDownloadPreferences.default.decisionParameters(
                for: item,
                source: PlexPlaybackSource(mediaIndex: 1, partIndex: 0),
                sessionIdentifier: "download-session"
            )
        }
        #expect(throws: PlexDownloadPreferencesError.invalidMediaSource) {
            _ = try PlexDownloadPreferences.default.decisionParameters(
                for: item,
                source: PlexPlaybackSource(mediaIndex: 0, partIndex: -1),
                sessionIdentifier: "download-session"
            )
        }
    }

    private static let fourKVideoJSON = #"""
    {
      "ratingKey": "42",
      "key": "/library/metadata/42",
      "title": "Movie",
      "type": "movie",
      "Media": [{
        "videoCodec": "hevc",
        "audioCodec": "aac",
        "width": 3840,
        "height": 2160,
        "bitrate": 30000,
        "Part": [{"key": "/library/parts/7/file.mkv"}]
      }]
    }
    """#
}

private func decodeDownloadItem(_ json: String) throws -> PlexMediaItem {
    try JSONDecoder().decode(PlexMediaItem.self, from: Data(json.utf8))
}
