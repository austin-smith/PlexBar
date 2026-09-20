@testable import PlexClientKit
import PlexModels
import Foundation
import Testing
@testable import PlexBar

@MainActor
struct PlexMainNavigationStoreTests {
    @Test func showMediaOpensTheExactItemFromTheHomeNavigationRoot() throws {
        let item = try mediaItem(ratingKey: "42", title: "Current Item")
        let store = PlexMainNavigationStore()
        store.selection = .history
        store.homeNavigationPath = [.media(PlexMediaRoute(ratingKey: "old")!)]

        store.showMedia(item)

        #expect(store.selection == .home)
        #expect(store.homeNavigationPath == [.media(PlexMediaRoute(item: item))])
    }

    @Test func serverChangeClearsEveryPrimaryNavigationPath() throws {
        let route = PlexNavigationRoute.media(
            PlexMediaRoute(item: try mediaItem(ratingKey: "42", title: "Item"))
        )
        let store = PlexMainNavigationStore()
        store.selection = .library("movies")
        store.homeNavigationPath = [route]
        store.historyNavigationPath = [route]
        store.collectionsNavigationPath = [route]
        store.playlistsNavigationPath = [route]

        store.resetForServerChange()

        #expect(store.selection == .home)
        #expect(store.homeNavigationPath.isEmpty)
        #expect(store.historyNavigationPath.isEmpty)
        #expect(store.collectionsNavigationPath.isEmpty)
        #expect(store.playlistsNavigationPath.isEmpty)
    }

    @Test func playerLibraryHandoffRequiresTheExactActiveServer() {
        #expect(PlexPlayerLibraryHandoffPolicy.canOpen(
            playbackServerIdentifier: "server-a",
            browserServerIdentifier: "server-a"
        ))
        #expect(!PlexPlayerLibraryHandoffPolicy.canOpen(
            playbackServerIdentifier: "server-a",
            browserServerIdentifier: "server-b"
        ))
        #expect(!PlexPlayerLibraryHandoffPolicy.canOpen(
            playbackServerIdentifier: nil,
            browserServerIdentifier: "server-a"
        ))
        #expect(!PlexPlayerLibraryHandoffPolicy.canOpen(
            playbackServerIdentifier: "server-a",
            browserServerIdentifier: "   "
        ))
    }

    private func mediaItem(ratingKey: String, title: String) throws -> PlexMediaItem {
        try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(#"{"ratingKey":"\#(ratingKey)","title":"\#(title)","type":"movie"}"#.utf8)
        )
    }
}
