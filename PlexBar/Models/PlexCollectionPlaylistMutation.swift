import Foundation

enum PlexListMoveDirection: Sendable {
    case up
    case down
}

extension PlexMediaItem {
    var playlistMediaType: String? {
        switch type?.lowercased() {
        case "movie", "show", "season", "episode", "clip":
            "video"
        case "artist", "album", "track":
            "audio"
        case "photo", "photoalbum":
            "photo"
        default:
            nil
        }
    }
}
