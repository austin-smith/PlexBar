import SwiftUI

extension PlexMediaItem {
    var usesCinematicDetailHero: Bool {
        guard let type = type?.lowercased() else {
            return false
        }
        return ["movie", "episode", "clip"].contains(type)
    }

    var usesCinematicHierarchyHero: Bool {
        guard let type = type?.lowercased() else {
            return false
        }
        return ["show", "season"].contains(type)
    }

    var placeholderSymbol: String {
        switch type?.lowercased() {
        case "show", "season", "episode": "tv"
        case "artist", "album", "track": "music.note"
        case "photo", "photoalbum": "photo"
        case "collection": "rectangle.stack"
        case "playlist": playlistType == "audio" ? "music.note.list" : "play.square.stack"
        case "playlistfolder": "folder"
        default: "film"
        }
    }

    var usesSquareArtwork: Bool {
        guard let type = type?.lowercased() else {
            return false
        }
        return [
            "artist", "album", "track", "photoalbum", "collection", "playlist", "playlistfolder"
        ].contains(type)
    }

    var usesLandscapeArtwork: Bool {
        guard let type = type?.lowercased() else {
            return false
        }
        return ["episode", "clip", "photo"].contains(type)
    }

    var detailArtworkHeight: CGFloat {
        if usesLandscapeArtwork {
            return 146
        }
        return usesSquareArtwork ? 260 : 390
    }

    var itemCountLabel: String? {
        leafCount.map { "\($0.formatted()) \($0 == 1 ? "item" : "items")" }
    }

    var watchStateAccessibilityValue: String? {
        if isWatched {
            return "Watched"
        }
        if let progress {
            return "\(progress.formatted(.percent.precision(.fractionLength(0)))) watched"
        }
        return supportsWatchedStateMutation ? "Unwatched" : nil
    }

}
