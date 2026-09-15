import PlexModels
import Foundation

struct PlexMediaFactsPresentation {
    let facts: [String]
    let contentRating: String?

    init(facts: [String?], contentRating: String?) {
        self.facts = facts.compactMap { $0?.nilIfBlank }
        self.contentRating = contentRating?.nilIfBlank
    }

    func plainText(separator: String = " · ") -> String? {
        (facts + [contentRating].compactMap { $0 }).joined(separator: separator).nilIfBlank
    }
}

/// Summary content shared by the Mac and TV detail layouts.
struct PlexMediaSummaryPresentation {
    let item: PlexMediaItem

    var episodeHeading: String {
        PlexEpisodeText.subtitle(season: item.parentIndex, episode: item.index, title: item.title)
    }

    var episodeFacts: String? {
        episodeFactsPresentation.plainText(separator: "  ·  ")
    }

    var episodeFactsPresentation: PlexMediaFactsPresentation {
        PlexMediaFactsPresentation(
            facts: [
                item.formattedDuration,
                PlexMediaMetadataPresentation(item: item).facts.first { $0.kind == .releaseDate }?.value,
            ],
            contentRating: item.contentRating
        )
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
        factsPresentation.plainText()
    }

    var factsPresentation: PlexMediaFactsPresentation {
        PlexMediaFactsPresentation(
            facts: [episodeIdentifier, year.map(String.init), formattedDuration],
            contentRating: contentRating
        )
    }
}
