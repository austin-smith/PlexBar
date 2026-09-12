import Foundation

enum PlexMediaArtworkLayout: Equatable, Sendable {
    case automatic
    case poster
}

enum PlexMediaArtworkShape: Sendable {
    case poster
    case landscape
    case square

    var aspectRatio: Double {
        switch self {
        case .poster: 2.0 / 3.0
        case .landscape: 16.0 / 9.0
        case .square: 1
        }
    }

    static func automatic(for item: PlexMediaItem) -> Self {
        switch item.type?.lowercased() {
        case "episode", "clip": .landscape
        case "artist", "album", "track", "photo", "photoalbum", "collection", "playlist": .square
        default: .poster
        }
    }
}

struct PlexMediaArtworkPresentation: Sendable {
    let shape: PlexMediaArtworkShape
    let path: String?

    init(item: PlexMediaItem, layout: PlexMediaArtworkLayout = .automatic) {
        switch layout {
        case .automatic:
            shape = .automatic(for: item)
            path = item.preferredArtworkPath
        case .poster:
            shape = .poster
            path = item.posterArtworkPath
        }
    }
}
