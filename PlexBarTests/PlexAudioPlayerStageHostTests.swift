import AppKit
import Foundation
import Testing
@testable import PlexBar

@MainActor
struct PlexAudioPlayerStageHostTests {
    @Test func videoPresentationDoesNotInstallAudioStage() {
        let overlayView = NSView()
        let host = PlexAudioPlayerStageHost()

        host.update(in: overlayView, overlay: nil)

        #expect(host.hostingView == nil)
        #expect(overlayView.subviews.isEmpty)
    }

    @Test func audioStageFillsOverlayWithoutContributingContentSizing() throws {
        let overlayView = NSView()
        let host = PlexAudioPlayerStageHost()

        host.update(in: overlayView, overlay: try audioOverlay())

        let hostingView = try #require(host.hostingView)
        #expect(hostingView.superview === overlayView)
        #expect(hostingView.sizingOptions.isEmpty)
        #expect(hostingView.translatesAutoresizingMaskIntoConstraints == false)
        #expect(overlayView.constraints.count == 4)
    }

    @Test func returningToVideoRemovesAudioStageFromLayout() throws {
        let overlayView = NSView()
        let host = PlexAudioPlayerStageHost()

        host.update(in: overlayView, overlay: try audioOverlay())
        let hostingView = try #require(host.hostingView)

        host.update(in: overlayView, overlay: nil)

        #expect(host.hostingView == nil)
        #expect(hostingView.superview == nil)
        #expect(overlayView.subviews.isEmpty)
    }

    @Test func audioStageMovesToReplacementAVKitOverlay() throws {
        let firstOverlayView = NSView()
        let replacementOverlayView = NSView()
        let host = PlexAudioPlayerStageHost()
        let overlay = try audioOverlay()

        host.update(in: firstOverlayView, overlay: overlay)
        let hostingView = try #require(host.hostingView)
        host.update(in: replacementOverlayView, overlay: overlay)

        #expect(host.hostingView === hostingView)
        #expect(hostingView.superview === replacementOverlayView)
        #expect(firstOverlayView.subviews.isEmpty)
        #expect(replacementOverlayView.subviews == [hostingView])
    }

    private func audioOverlay() throws -> PlexAudioPlayerOverlay {
        let item = try JSONDecoder().decode(PlexMediaItem.self, from: Data(#"""
        {
          "ratingKey": "track-9",
          "title": "Chapter 3",
          "type": "track",
          "parentTitle": "Kitchen Confidential",
          "parentThumb": "/library/metadata/9/thumb",
          "Media": [{"audioCodec": "aac", "Part": [{"id": "50"}]}]
        }
        """#.utf8))
        let presentation = try #require(PlexAudioPlaybackPresentation(
            item: item,
            source: PlexPlaybackSource(mediaIndex: 0, partIndex: 0)
        ))

        return PlexAudioPlayerOverlay(
            presentation: presentation,
            serverURL: URL(string: "https://plex.example"),
            token: "token",
            clientContext: PlexClientContext(clientIdentifier: "player-stage-test")
        )
    }
}
