import PlexModels
import Foundation

public enum PlexMediaArtworkLayout: Equatable, Sendable {
    case automatic
    case poster
}

public enum PlexMediaArtworkShape: Sendable {
    case poster
    case landscape
    case square

    public var aspectRatio: Double {
        switch self {
        case .poster: 2.0 / 3.0
        case .landscape: 16.0 / 9.0
        case .square: 1
        }
    }

    public static func automatic(for item: PlexMediaItem) -> Self {
        switch item.type?.lowercased() {
        case "episode", "clip": .landscape
        case "artist", "album", "track", "photo", "photoalbum", "collection", "playlist": .square
        default: .poster
        }
    }
}

public struct PlexMediaArtworkPresentation: Sendable {
    public let shape: PlexMediaArtworkShape
    public let path: String?

    public init(item: PlexMediaItem, layout: PlexMediaArtworkLayout = .automatic) {
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
