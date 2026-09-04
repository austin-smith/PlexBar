import Foundation
import Testing
@testable import PlexBar

struct PlexEpisodeSpoilerPresentationTests {
    @Test func policyUsesOnlyAuthoritativeEpisodeWatchState() throws {
        let unwatchedEpisode = try item(
            #"{"ratingKey":"1","type":"episode","title":"Unwatched","viewCount":0,"viewOffset":120000}"#
        )
        let watchedEpisode = try item(
            #"{"ratingKey":"2","type":"episode","title":"Watched","viewCount":1}"#
        )
        let movie = try item(
            #"{"ratingKey":"3","type":"movie","title":"Movie","viewCount":0}"#
        )

        #expect(!PlexEpisodeSpoilerPolicy.off.hidesSpoilers(for: unwatchedEpisode))
        #expect(PlexEpisodeSpoilerPolicy.unwatchedEpisodes.hidesSpoilers(for: unwatchedEpisode))
        #expect(!PlexEpisodeSpoilerPolicy.unwatchedEpisodes.hidesSpoilers(for: watchedEpisode))
        #expect(PlexEpisodeSpoilerPolicy.allEpisodes.hidesSpoilers(for: watchedEpisode))
        #expect(!PlexEpisodeSpoilerPolicy.allEpisodes.hidesSpoilers(for: movie))
    }

    @Test func protectedEpisodesExposeNeitherSummaryNorThumbnailPath() throws {
        let episode = try item(
            #"{"ratingKey":"1","type":"episode","title":"Episode","summary":"The reveal.","thumb":"/library/metadata/1/thumb"}"#
        )

        let protected = PlexEpisodeSpoilerPresentation(
            item: episode,
            policy: .unwatchedEpisodes
        )
        let visible = PlexEpisodeSpoilerPresentation(item: episode, policy: .off)

        #expect(protected.isProtected)
        #expect(protected.summary == nil)
        #expect(protected.thumbnailPath == nil)
        #expect(!visible.isProtected)
        #expect(visible.summary == "The reveal.")
        #expect(visible.thumbnailPath == "/library/metadata/1/thumb")
    }

    @MainActor
    @Test func posterPrefetchRemainsAvailableWhileProtectedThumbnailPrefetchIsOmitted() throws {
        let episode = try item(
            #"{"ratingKey":"1","type":"episode","title":"Episode","thumb":"/library/metadata/1/thumb","grandparentThumb":"/library/metadata/10/thumb"}"#
        )
        let serverURL = try #require(URL(string: "https://plex.example"))
        let clientContext = PlexClientContext(clientIdentifier: "client")

        let thumbnailRequest = PlexMediaPosterCard.prefetchRequest(
            for: episode,
            serverURL: serverURL,
            token: "token",
            clientContext: clientContext,
            artworkLayout: .automatic,
            spoilerPolicy: .unwatchedEpisodes
        )
        let posterRequest = PlexMediaPosterCard.prefetchRequest(
            for: episode,
            serverURL: serverURL,
            token: "token",
            clientContext: clientContext,
            artworkLayout: .poster,
            spoilerPolicy: .unwatchedEpisodes
        )

        #expect(thumbnailRequest == nil)
        #expect(posterRequest?.candidateURLs.map(\.path) == ["/library/metadata/10/thumb"])
    }

    @Test func posterIntentNeverFallsBackToAnEpisodeScreenshot() throws {
        let episode = try item(
            #"{"ratingKey":"1","type":"episode","title":"Episode","thumb":"/library/metadata/1/thumb"}"#
        )

        #expect(episode.posterArtworkPath == nil)
        #expect(episode.nowPlayingArtworkPaths.isEmpty)
    }

    private func item(_ json: String) throws -> PlexMediaItem {
        try JSONDecoder().decode(PlexMediaItem.self, from: Data(json.utf8))
    }
}
