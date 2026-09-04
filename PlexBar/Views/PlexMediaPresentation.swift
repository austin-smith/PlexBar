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

    var formattedDuration: String? {
        guard let duration, duration > 0 else {
            return nil
        }

        let roundedMinutes = max((Int64(duration) + 30_000) / 60_000, 1)
        return Duration.seconds(roundedMinutes * 60)
            .formatted(.units(width: .abbreviated))
            .replacingOccurrences(of: ", ", with: " ")
    }

    var preferredArtworkPath: String? {
        thumb?.nilIfBlank ?? composite?.nilIfBlank
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

    var episodeIdentifier: String? {
        guard type?.lowercased() == "episode", let index else {
            return nil
        }
        if let parentIndex {
            return "S\(parentIndex), E\(index)"
        }
        return "Episode \(index)"
    }

    var factsLine: String? {
        let values = [episodeIdentifier, year.map(String.init), formattedDuration, contentRating?.nilIfBlank]
            .compactMap { $0 }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }
}
