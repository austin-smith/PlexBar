import PlexClientKit
import PlexModels
import Observation

@MainActor
@Observable
final class PlexMainNavigationStore {
    static let windowID = "main"

    var selection: PlexMainSection? = .home
    var homeNavigationPath: [PlexNavigationRoute] = []
    var historyNavigationPath: [PlexNavigationRoute] = []
    var collectionsNavigationPath: [PlexNavigationRoute] = []
    var playlistsNavigationPath: [PlexNavigationRoute] = []

    func showMedia(_ item: PlexMediaItem) {
        selection = .home
        homeNavigationPath = [.media(PlexMediaRoute(item: item))]
    }

    func openRoot(_ section: PlexMainSection) {
        selection = section
        switch section {
        case .home: homeNavigationPath.removeAll()
        case .history: historyNavigationPath.removeAll()
        case .collections: collectionsNavigationPath.removeAll()
        case .playlists: playlistsNavigationPath.removeAll()
        case .downloads, .library, .activity, .users: break
        }
    }

    func resetForServerChange() {
        selection = .home
        homeNavigationPath.removeAll()
        historyNavigationPath.removeAll()
        collectionsNavigationPath.removeAll()
        playlistsNavigationPath.removeAll()
    }
}

enum PlexMainSection: Hashable, Sendable {
    case home
    case downloads
    case library(String)
    case collections
    case playlists
    case activity
    case history
    case users

    var title: String {
        switch self {
        case .home: "Home"
        case .downloads: "Downloads"
        case .library: "Library"
        case .collections: "Collections"
        case .playlists: "Playlists"
        case .activity: "Activity"
        case .history: "History"
        case .users: "Users"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .downloads: "arrow.down.circle"
        case .library: "books.vertical"
        case .collections: "rectangle.stack"
        case .playlists: "music.note.list"
        case .activity: "play.rectangle.on.rectangle"
        case .history: "clock.arrow.circlepath"
        case .users: "person.2"
        }
    }
}
