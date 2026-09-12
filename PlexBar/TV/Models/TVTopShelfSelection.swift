import Foundation

struct TVTopShelfSelection: Sendable {
    struct Section: Sendable {
        let identifier: String
        let title: String
        let items: [PlexMediaItem]
    }

    let sections: [Section]

    init(hubs: [PlexHub]) {
        // Preserve the server's library order, with Continue Watching first.
        // /hubs/promoted may return either home hubs or promoted per-library hubs.
        let selectedHubs = hubs.filter(\.isContinueWatching)
            + hubs.filter { Self.isRecentlyAdded($0.hubIdentifier) }
        var seen: Set<String> = []
        var remainingItems = 40
        sections = selectedHubs.compactMap { hub in
            guard remainingItems > 0 else { return nil }
            var items: [PlexMediaItem] = []
            for item in hub.metadata {
                guard TVTopShelfRoute.isValidRatingKey(item.ratingKey),
                      ["movie", "show", "season", "episode", "album", "track"].contains(item.type?.lowercased() ?? ""),
                      Self.artworkPath(for: item) != nil,
                      seen.insert(item.ratingKey).inserted else { continue }
                items.append(item)
                remainingItems -= 1
                if items.count == 10 || remainingItems == 0 { break }
            }
            guard !items.isEmpty else { return nil }
            return Section(identifier: hub.hubIdentifier, title: hub.title, items: items)
        }
    }

    private static func isRecentlyAdded(_ identifier: String) -> Bool {
        let identifier = identifier.lowercased()
        if ["home.movies.recent", "home.television.recent", "home.music.recent"].contains(identifier) { return true }
        let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 4, parts[0] == "music", parts[1] == "recent", parts[2] == "added" {
            return TVTopShelfRoute.isValidRatingKey(String(parts[3]))
        }
        guard parts.count == 3,
              ["movie", "tv", "music"].contains(parts[0]),
              parts[1] == "recentlyadded",
              TVTopShelfRoute.isValidRatingKey(String(parts[2])) else { return false }
        return true
    }

    static func artworkPath(for item: PlexMediaItem) -> String? {
        item.posterArtworkPath
    }

    static func shape(for item: PlexMediaItem) -> TVTopShelfSnapshot.Item.Shape {
        ["album", "track"].contains(item.type?.lowercased() ?? "") ? .square : .poster
    }

    static func title(for item: PlexMediaItem) -> String {
        if item.type?.lowercased() == "episode" {
            return [item.grandparentTitle, item.tvEpisodeTitle].compactMap { $0?.nilIfBlank }.joined(separator: " — ")
        }
        return item.title
    }

    static func progress(for item: PlexMediaItem) -> Double {
        guard let duration = item.duration, duration > 0, let offset = item.viewOffset else { return 0 }
        return min(max(Double(offset) / Double(duration), 0), 1)
    }
}
