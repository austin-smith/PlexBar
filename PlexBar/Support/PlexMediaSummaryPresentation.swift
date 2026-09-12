import Foundation

enum PlexEpisodeText {
    static func numbers(season: Int?, episode: Int?) -> String? {
        [season.map { "S\($0)" }, episode.map { "E\($0)" }]
            .compactMap { $0 }
            .joined(separator: " • ")
            .nilIfBlank
    }

    static func subtitle(season: Int?, episode: Int?, title: String) -> String {
        [numbers(season: season, episode: episode), title.nilIfBlank]
            .compactMap { $0 }
            .joined(separator: " - ")
    }
}

/// Summary content shared by the Mac and TV detail layouts.
struct PlexMediaSummaryPresentation {
    let item: PlexMediaItem

    var episodeHeading: String {
        PlexEpisodeText.subtitle(season: item.parentIndex, episode: item.index, title: item.title)
    }

    var episodeFacts: String? {
        [
            item.formattedDuration,
            PlexMediaMetadataPresentation(item: item).facts.first { $0.kind == .releaseDate }?.value,
            item.contentRating?.nilIfBlank,
        ]
        .compactMap { $0 }
        .joined(separator: "  ·  ")
        .nilIfBlank
    }

    var heroFacts: String? {
        item.factsLine
    }

    var genres: String? {
        item.genres.prefix(3).map(\.tag).joined(separator: ", ").nilIfBlank
    }

    var detailFacts: String? {
        item.type?.lowercased() == "episode" ? episodeFacts : heroFacts
    }
}

extension PlexMediaItem {
    var episodeIdentifier: String? {
        guard type?.lowercased() == "episode", let index else { return nil }
        if let parentIndex { return "S\(parentIndex), E\(index)" }
        return "Episode \(index)"
    }

    var factsLine: String? {
        let values = [episodeIdentifier, year.map(String.init), formattedDuration, contentRating?.nilIfBlank]
            .compactMap { $0 }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }
}
