import PlexModels
import Foundation
import Testing
@testable import PlexBar

struct PlexPlayerInfoTests {
    @Test func playbackVersionsUseSharedExactSourcesAndHumanReadableFacts() throws {
        let movie = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(#"""
            {
              "ratingKey": "42",
              "type": "movie",
              "title": "Blade Runner",
              "Media": [
                {
                  "width": 1920,
                  "height": 1080,
                  "videoCodec": "h264",
                  "bitrate": 12000,
                  "container": "mkv",
                  "Part": [{ "key": "/library/parts/1/movie.mkv" }]
                },
                {
                  "videoResolution": "4k",
                  "videoCodec": "hevc",
                  "bitrate": 48720,
                  "container": "mkv",
                  "Part": [{ "key": "/library/parts/2/movie.mkv" }]
                },
                {
                  "videoResolution": "sd",
                  "videoCodec": "h264",
                  "container": "mp4"
                }
              ]
            }
            """#.utf8)
        )

        let selection = try #require(PlexPlaybackVersionSelection(
            item: movie,
            selectedSource: PlexPlaybackSource(mediaIndex: 1, partIndex: 0)
        ))

        #expect(selection.options.map(\.id) == [0, 1])
        #expect(selection.options.map(\.label) == [
            "Version 1 · 1920 × 1080 · H264 · 12 Mbps · MKV",
            "Version 2 · 4K · HEVC · 48.7 Mbps · MKV",
        ])
        #expect(selection.selectedID == 1)
        #expect(selection.selectedOption?.id == 1)
        #expect(selection.source(for: 0) == PlexPlaybackSource(mediaIndex: 0, partIndex: 0))
        #expect(selection.source(for: 1) == nil)
        #expect(selection.source(for: 2) == nil)
    }

    @Test func playbackVersionMenuRequiresMultiplePlayableVersions() throws {
        let track = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(#"""
            {
              "ratingKey": "84",
              "type": "track",
              "title": "Roads",
              "Media": [{
                "audioCodec": "flac",
                "bitrate": 921,
                "container": "flac",
                "Part": [{ "key": "/library/parts/3/roads.flac" }]
              }]
            }
            """#.utf8)
        )
        let source = try #require(track.defaultPlaybackSource)

        #expect(track.playbackVersionOptions.map(\.label) == [
            "Version 1 · FLAC · 921 kbps · FLAC",
        ])
        #expect(PlexPlaybackVersionSelection(item: track, selectedSource: source) == nil)
    }

    @Test func playbackInfoUsesOnlyCurrentItemIdentityAndHierarchy() throws {
        let episode = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(#"""
            {
              "ratingKey": "42",
              "type": "episode",
              "title": "Good News About Hell",
              "grandparentTitle": "Severance",
              "parentTitle": "Season 1",
              "parentIndex": 1,
              "index": 1,
              "year": 2022,
              "duration": 3420000,
              "summary": "  Mark starts a new job.  ",
              "contentRating": " TV-MA ",
              "Genre": [
                { "tag": "Drama" },
                { "tag": "Thriller" },
                { "tag": "Drama" },
                { "tag": "   " }
              ]
            }
            """#.utf8)
        )

        let presentation = PlexPlayerPlaybackInfoPresentation(item: episode)

        #expect(presentation.title == "Good News About Hell")
        #expect(presentation.hierarchyLine == "Severance · Season 1")
        #expect(presentation.summary == "Mark starts a new job.")
        #expect(presentation.contentRating == "TV-MA")
        #expect(presentation.genre == "Drama, Thriller")
    }

    @Test func playbackInfoRemovesRepeatedHierarchyLabels() throws {
        let track = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(#"""
            {
              "ratingKey": "84",
              "type": "track",
              "title": "Chapter 1",
              "grandparentTitle": "The Author",
              "parentTitle": "The Author",
              "summary": "   "
            }
            """#.utf8)
        )

        let presentation = PlexPlayerPlaybackInfoPresentation(item: track)

        #expect(presentation.hierarchyLine == "The Author")
        #expect(presentation.summary == nil)
        #expect(presentation.contentRating == nil)
        #expect(presentation.genre == nil)
    }

    @Test func playbackInfoBuildsStableSharedPlaybackRows() throws {
        let movie = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(#"{"ratingKey":"9","type":"movie","title":"Arrival"}"#.utf8)
        )

        var metrics = PlexPlaybackMetricFacts()
        metrics.recordStall()

        let presentation = PlexPlaybackInfoPresentation(
            item: movie,
            deliveryLabel: "Direct Stream",
            connectionLabel: "Remote",
            videoQualityLabel: "1080p · 12 Mbps",
            playbackVersionLabel: "Version 2 · 4K · HEVC",
            queuePositionLabel: "2 of 8",
            waitingReasonLabel: "Minimizing Stalls",
            audioOutputLabel: "Dolby Atmos",
            deliveredMediaFacts: nil,
            playbackMetricFacts: metrics.diagnosticFacts
        )

        #expect(presentation.playbackRows.map(\.id) == [
            "delivery",
            "connection",
            "quality",
            "version",
            "queue",
            "waiting",
        ])
        #expect(presentation.playbackRows.map(\.value) == [
            "Direct Stream",
            "Remote",
            "1080p · 12 Mbps",
            "Version 2 · 4K · HEVC",
            "2 of 8",
            "Minimizing Stalls",
        ])
        #expect(presentation.videoRows.isEmpty)
        #expect(presentation.audioRows.map(\.id) == ["output"])
        #expect(presentation.audioRows.map(\.value) == ["Dolby Atmos"])
        #expect(presentation.performanceRows.map(\.id) == ["metric.stalls"])
        #expect(presentation.performanceRows.map(\.value) == ["1"])
    }

    @Test func playerUsesOneMutuallyExclusiveInPlayerOverlay() {
        var selection = PlexPlayerOverlaySelection()

        #expect(!selection.isPresented)
        #expect(selection.selected == nil)

        selection.toggle(.info)
        #expect(selection.isPresented)
        #expect(selection.selected == .info)

        selection.toggle(.upNext)
        #expect(selection.selected == .upNext)

        selection.toggle(.upNext)
        #expect(!selection.isPresented)

        selection.toggle(.info)
        selection.dismiss()
        #expect(selection.selected == nil)
    }

    @Test func playerOverlayCommandsDescribeTheActionTheyWillPerform() {
        var selection = PlexPlayerOverlaySelection()

        #expect(selection.commandTitle(for: .info) == "Show Playback Info")
        #expect(selection.commandTitle(for: .upNext) == "Show Up Next")

        selection.present(.info)
        #expect(selection.commandTitle(for: .info) == "Hide Playback Info")
        #expect(selection.commandTitle(for: .upNext) == "Show Up Next")

        selection.present(.upNext)
        #expect(selection.commandTitle(for: .info) == "Show Playback Info")
        #expect(selection.commandTitle(for: .upNext) == "Hide Up Next")
    }

    @Test func currentItemMutationTicketRejectsAQueueTransition() throws {
        let current = try playbackPresentation(
            ratingKey: "42",
            title: "Current",
            sessionIdentifier: "session-current"
        )
        let ticket = PlexPlayerItemMutationTicket(presentation: current)

        #expect(ticket.accepts(current))
        #expect(!ticket.accepts(try playbackPresentation(
            ratingKey: "43",
            title: "Next",
            sessionIdentifier: "session-next"
        )))
        #expect(!ticket.accepts(try playbackPresentation(
            ratingKey: "42",
            title: "Repeated Later",
            sessionIdentifier: "session-repeat"
        )))
    }

    private func playbackPresentation(
        ratingKey: String,
        title: String,
        sessionIdentifier: String
    ) throws -> PlexPlaybackPresentation {
        let item = try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(#"{"ratingKey":"\#(ratingKey)","title":"\#(title)","type":"movie"}"#.utf8)
        )
        let source = PlexPlaybackSource(
            mediaIndex: 0,
            partIndex: 0
        )
        let plan = PlexPlaybackPlan(
            url: URL(string: "https://example.com/video.mkv")!,
            method: .directPlay,
            mediaKind: .video,
            sessionIdentifier: sessionIdentifier,
            ratingKey: ratingKey,
            duration: nil,
            startTime: 0,
            source: source,
            usesServerMediaSelection: false
        )
        return PlexPlaybackPresentation(
            item: item,
            plan: plan,
            queue: nil,
            videoQuality: .original
        )
    }
}
