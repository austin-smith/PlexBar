import PlexModels
import Foundation
import Testing
@testable import PlexBar

@MainActor
@Suite(.serialized)
struct PlexLibraryPresentationStoreTests {
    @Test func synchronizeRetainsIndependentPresentationStateForActiveLibraries() throws {
        let store = PlexLibraryPresentationStore()
        store.synchronize(libraryIDs: ["movies", "shows"])

        let movies = try #require(store.state(for: "movies"))
        let shows = try #require(store.state(for: "shows"))
        let movie = try decodeItem(ratingKey: "101", title: "Movie")
        movies.navigationPath = [.media(PlexMediaRoute(item: movie))]
        movies.searchStore.text = "science fiction"
        movies.scrollPosition.scrollTo(id: movie.id, anchor: .top)

        store.synchronize(libraryIDs: ["movies", "shows"])

        let retainedMovies = try #require(store.state(for: "movies"))
        let retainedShows = try #require(store.state(for: "shows"))
        #expect(retainedMovies === movies)
        #expect(retainedShows === shows)
        #expect(retainedMovies.navigationPath == [.media(PlexMediaRoute(item: movie))])
        #expect(retainedMovies.searchStore.text == "science fiction")
        #expect(retainedMovies.scrollPosition.viewID(type: String.self) == movie.id)
        #expect(retainedShows.navigationPath.isEmpty)
        #expect(retainedShows.searchStore.text.isEmpty)
    }

    @Test func synchronizeRemovesLibrariesThatAreNoLongerAvailable() throws {
        let store = PlexLibraryPresentationStore()
        store.synchronize(libraryIDs: ["movies", "shows"])
        let shows = try #require(store.state(for: "shows"))

        store.synchronize(libraryIDs: ["shows"])

        #expect(store.state(for: "movies") == nil)
        #expect(store.state(for: "shows") === shows)
    }

    @Test func removeAllInvalidatesEveryServerScopedPresentationState() {
        let store = PlexLibraryPresentationStore()
        store.synchronize(libraryIDs: ["movies", "shows"])

        store.removeAll()

        #expect(store.state(for: "movies") == nil)
        #expect(store.state(for: "shows") == nil)
    }

    @Test func mediaRouteUsesLightweightListIdentityAndRatingKey() throws {
        let first = try decodeItem(
            ratingKey: "404",
            title: "First Copy",
            playlistItemID: "playlist-entry-1"
        )
        let second = try decodeItem(
            ratingKey: "404",
            title: "Second Copy",
            playlistItemID: "playlist-entry-2"
        )
        let route = PlexMediaRoute(item: first)

        #expect(route.matches(first))
        #expect(!route.matches(second))
        #expect(route.ratingKey == "404")
        #expect(route.itemID == "playlist-item:playlist-entry-1")
    }

    private func decodeItem(
        ratingKey: String,
        title: String,
        playlistItemID: String? = nil
    ) throws -> PlexMediaItem {
        var object: [String: Any] = [
            "ratingKey": ratingKey,
            "title": title,
            "type": "movie",
        ]
        object["playlistItemID"] = playlistItemID
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(PlexMediaItem.self, from: data)
    }
}
