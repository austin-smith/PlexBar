import PlexModels
import Foundation

public struct PlexMediaFactsPresentation {
    public let facts: [String]
    public let contentRating: String?

    public init(facts: [String?], contentRating: String?) {
        self.facts = facts.compactMap { $0?.nilIfBlank }
        self.contentRating = contentRating?.nilIfBlank
    }

    public func plainText(separator: String = " · ") -> String? {
        (facts + [contentRating].compactMap { $0 }).joined(separator: separator).nilIfBlank
    }
}

/// Summary content shared by the Mac and TV detail layouts.
public struct PlexMediaSummaryPresentation {
    public let item: PlexMediaItem

    public var episodeHeading: String {
        PlexEpisodeText.subtitle(season: item.parentIndex, episode: item.index, title: item.title)
    }

    public var episodeFacts: String? {
        episodeFactsPresentation.plainText(separator: "  ·  ")
    }

    public var episodeFactsPresentation: PlexMediaFactsPresentation {
        PlexMediaFactsPresentation(
            facts: [
                item.formattedDuration,
                PlexMediaMetadataPresentation(item: item).facts.first { $0.kind == .releaseDate }?.value,
            ],
            contentRating: item.contentRating
        )
    }

    public var heroFacts: String? {
        item.factsLine
    }

    public var genres: String? {
        item.genres.prefix(3).map(\.tag).joined(separator: ", ").nilIfBlank
    }

    public var detailFacts: String? {
        item.type?.lowercased() == "episode" ? episodeFacts : heroFacts
    }

    public init(item: PlexMediaItem) {
        self.item = item
    }
}

extension PlexMediaItem {
    public var episodeIdentifier: String? {
        guard type?.lowercased() == "episode", let index else { return nil }
        if let parentIndex { return "S\(parentIndex), E\(index)" }
        return "Episode \(index)"
    }

    public var factsLine: String? {
        factsPresentation.plainText()
    }

    public var factsPresentation: PlexMediaFactsPresentation {
        PlexMediaFactsPresentation(
            facts: [episodeIdentifier, year.map(String.init), formattedDuration],
            contentRating: contentRating
        )
    }
}
