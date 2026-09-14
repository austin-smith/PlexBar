import PlexModels
import Foundation
import Testing
@testable import PlexBar

struct PlexMediaFactsPresentationTests {
    @Test(arguments: [
        "TV-Y", "TV-Y7", "TV-Y7-FV", "TV-G", "TV-PG", "TV-14", "TV-MA",
        "G", "PG", "PG-13", "R", "NC-17", "U", "12A", "15", "18",
        "FSK 16", "au/MA15+", "TV-MA (L, S, V)", "NR", "Unrated", "Custom classification",
    ])
    func preservesContentRatingsSeparatelyFromOtherFacts(rating: String) throws {
        let item = try makeItem(type: "movie", contentRating: " \(rating)\n", year: 2025)

        #expect(item.factsPresentation.facts == ["2025"])
        #expect(item.factsPresentation.contentRating == rating)
        #expect(item.factsLine == "2025 · \(rating)")
    }

    @Test(arguments: [nil, "", " \n\t "] as [String?])
    func missingRatingsDoNotBecomeUnratedOrLeaveSeparators(rating: String?) throws {
        let item = try makeItem(type: "movie", contentRating: rating, year: 2025)
        let empty = try makeItem(type: "episode", contentRating: rating)

        #expect(item.factsPresentation.contentRating == nil)
        #expect(item.factsLine == "2025")
        #expect(empty.factsPresentation.facts.isEmpty)
        #expect(empty.factsPresentation.contentRating == nil)
        #expect(empty.factsLine == nil)
        #expect(PlexMediaSummaryPresentation(item: empty).episodeFacts == nil)
    }

    @Test func ratingWithoutOtherFactsRemainsVisible() throws {
        let item = try makeItem(type: "movie", contentRating: "NR")

        #expect(item.factsPresentation.facts.isEmpty)
        #expect(item.factsPresentation.contentRating == "NR")
        #expect(item.factsLine == "NR")
    }

    @Test func episodeFactsUseEpisodeClassificationAndKeepReleaseDateOutsideBadge() throws {
        let episode = try JSONDecoder().decode(PlexMediaItem.self, from: Data(#"""
        {
          "ratingKey": "episode", "type": "episode", "title": "Episode",
          "duration": 2160000, "originallyAvailableAt": "2025-04-01",
          "parentIndex": 1, "index": 3, "contentRating": "TV-14"
        }
        """#.utf8))
        let presentation = PlexMediaSummaryPresentation(item: episode)
        let releaseDate = try #require(PlexMediaMetadataPresentation(item: episode).facts.first {
            $0.kind == .releaseDate
        }?.value)
        let duration = try #require(episode.formattedDuration)

        #expect(presentation.episodeFactsPresentation.facts == [duration, releaseDate])
        #expect(presentation.episodeFactsPresentation.contentRating == "TV-14")
        #expect(presentation.episodeFacts == "\(duration)  ·  \(releaseDate)  ·  TV-14")

        let otherEpisode = try makeItem(type: "episode", contentRating: "TV-MA")
        #expect(PlexMediaSummaryPresentation(item: otherEpisode).episodeFactsPresentation.contentRating == "TV-MA")
        let missingRatingEpisode = try makeItem(type: "episode", contentRating: nil)
        #expect(PlexMediaSummaryPresentation(item: missingRatingEpisode).episodeFactsPresentation.contentRating == nil)
    }

    private func makeItem(type: String, contentRating: String?, year: Int? = nil) throws -> PlexMediaItem {
        var json: [String: Any] = ["ratingKey": "item", "type": type, "title": "Title"]
        json["contentRating"] = contentRating
        json["year"] = year
        return try JSONDecoder().decode(PlexMediaItem.self, from: JSONSerialization.data(withJSONObject: json))
    }
}
