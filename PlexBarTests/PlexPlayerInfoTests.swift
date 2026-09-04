import Foundation
import Testing
@testable import PlexBar

struct PlexPlayerInfoTests {
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
              "summary": "Mark starts a new job."
            }
            """#.utf8)
        )

        let presentation = PlexPlayerPlaybackInfoPresentation(item: episode)

        #expect(presentation.title == "Good News About Hell")
        #expect(presentation.hierarchyLine == "Severance · Season 1")
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
