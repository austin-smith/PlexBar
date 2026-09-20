import PlexClientKit
import Foundation
import PlexModels

struct PlexPaletteResult: Identifiable, Equatable {
    enum ID: Hashable {
        case command(PlexPaletteCommand.ID)
        case media(String)
        case allResults
    }

    enum Content: Equatable {
        case command(PlexPaletteCommand)
        case media(PlexMediaItem, download: PlexOfflineMedia?)
        case allResults(String)
    }

    let content: Content
    let group: String
    var libraryTitle: String? = nil

    var id: ID {
        switch content {
        case .command(let command): .command(command.id)
        case .media(let item, _): .media(item.ratingKey)
        case .allResults: .allResults
        }
    }

    var title: String {
        switch content {
        case .command(let command): command.title
        case .media(let item, _): item.title
        case .allResults(let query): "Show all results for “\(query)”"
        }
    }

    var isEnabled: Bool {
        if case .command(let command) = content { return command.isEnabled }
        return true
    }

    var canPlay: Bool {
        guard case .media(let item, _) = content else { return false }
        return ["movie", "episode", "track", "clip", "trailer"].contains(item.type?.lowercased() ?? "")
    }

    func matchesTitleExactly(_ query: String) -> Bool {
        Self.normalized(title) == Self.normalized(query)
    }

    var playTitle: String {
        guard case .media(let item, let download) = content else { return "Play" }
        let action = item.hasResumePosition ? "Resume" : "Play"
        return download == nil ? action : "\(action) Download"
    }

    var subtitle: String? {
        switch content {
        case .command(let command): return command.unavailableReason
        case .allResults: return "Browse all matching library content"
        case .media(let item, let download):
            let kind: String = switch item.type?.lowercased() {
            case "movie": "Movie"
            case "show": "TV Show"
            case "season": "Season"
            case "episode": "Episode"
            case "artist": "Artist"
            case "album": "Album"
            case "track": "Track"
            case "collection": "Collection"
            case "playlist": "Playlist"
            case "photo": "Photo"
            default: item.type?.capitalized ?? "Library Item"
            }
            var parts: [String] = []
            if item.type == "episode" {
                if let show = item.grandparentTitle { parts.append(show) }
                if let season = item.parentIndex, let episode = item.index {
                    parts.append("S\(season) · E\(episode)")
                }
            } else if ["album", "track", "season"].contains(item.type ?? "") {
                if let parent = item.type == "track" ? item.grandparentTitle : item.parentTitle {
                    parts.append(parent)
                }
                if item.type == "track", let album = item.parentTitle { parts.append(album) }
            }
            if let year = item.year { parts.append(String(year)) }
            if !["album", "track"].contains(item.type ?? "") { parts.append(kind) }
            // Library names carry the user's actual classification (including audiobooks).
            if let library = libraryTitle ?? item.librarySectionTitle { parts.append(library) }
            else if ["album", "track"].contains(item.type ?? "") { parts.append(kind) }
            if download != nil { parts.append("Downloaded") }
            if let reason = item.reasonTitle, !parts.contains(reason) { parts.append(reason) }
            return parts.joined(separator: " · ")
        }
    }
}

extension PlexPaletteResult {
    static func mediaResults(
        hubs: [PlexHub], query: String, libraries: [PlexLibrary], downloads: [PlexOfflineMedia]
    ) -> [Self] {
        var seen = Set<String>()
        let exact = normalized(query)
        var top: [Self] = []
        var grouped: [Self] = []
        for hub in hubs {
            var count = 0
            for item in hub.metadata {
                let isExact = normalized(item.title) == exact
                guard isExact || count < 4 else { continue }
                guard seen.insert(item.ratingKey).inserted else { continue }
                let result = media(item, group: isExact ? "Top Results" : hub.title,
                                   libraries: libraries, downloads: downloads)
                if isExact { top.append(result) }
                else { grouped.append(result); count += 1 }
            }
        }
        return Array((top + grouped).prefix(12))
    }

    static func media(_ item: PlexMediaItem, group: String, libraries: [PlexLibrary], downloads: [PlexOfflineMedia]) -> Self {
        Self(content: .media(item, download: downloads.first { $0.item.ratingKey == item.ratingKey }),
             group: group, libraryTitle: libraries.first { $0.id == item.librarySectionID }?.title)
    }

    static func matches(_ item: PlexMediaItem, query: String) -> Bool {
        let text = normalized([item.title, item.originalTitle, item.parentTitle, item.grandparentTitle]
            .compactMap { $0 }.joined(separator: " "))
        return normalized(query).split(separator: " ").allSatisfy { text.contains($0) }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
