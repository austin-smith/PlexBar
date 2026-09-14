import PlexModels
import Foundation

enum TVHomeContent {
    static func videoItems(_ items: [PlexMediaItem]) -> [PlexMediaItem] {
        items.filter { item in
            switch item.type?.lowercased() {
            case "movie", "show", "season", "episode": true
            default: false
            }
        }
    }

    static func hubs(_ hubs: [PlexHub]) -> [PlexHub] {
        hubs.compactMap { hub in
            var hub = hub
            hub.metadata = videoItems(hub.metadata)
            return hub.metadata.isEmpty ? nil : hub
        }
    }
}
