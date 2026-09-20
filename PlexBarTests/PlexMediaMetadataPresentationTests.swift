@testable import PlexClientKit
import PlexModels
import Foundation
import Testing
@testable import PlexBar

struct PlexMediaMetadataPresentationTests {
    @Test func decodesAndLabelsPublishedPlexMetadataFields() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "42",
          "title": "Charade",
          "originalTitle": "The Unsuspected Wife",
          "type": "movie",
          "studio": "Universal Pictures",
          "originallyAvailableAt": "1963-12-05",
          "rating": 7.9,
          "ratingImage": "imdb://image.rating",
          "audienceRating": 8.2,
          "audienceRatingImage": "rottentomatoes://image.rating.upright",
          "Guid": [
            { "id": "imdb://tt0047437" },
            { "id": "tmdb://4808" }
          ],
          "Rating": [
            { "image": "imdb://image.rating", "type": "audience", "value": 7.9 },
            { "image": "rottentomatoes://image.rating.ripe", "type": "critic", "value": 8.6 },
            { "image": "rottentomatoes://image.rating.upright", "type": "audience", "value": 8.2 },
            { "image": "themoviedb://image.rating", "type": "audience", "value": 7.5 }
          ],
          "Genre": [
            { "tag": "Comedy" },
            { "tag": "Mystery" },
            { "tag": "Comedy" }
          ],
          "Director": [{ "tag": "Stanley Donen" }],
          "Writer": [
            { "tag": "Peter Stone" },
            { "tag": "Marc Behm" }
          ],
          "Role": [
            { "tag": "Cary Grant", "role": "Peter Joshua" },
            { "tag": "Audrey Hepburn", "role": "Regina Lampert" }
          ],
          "Country": [{ "tag": "United States" }]
        }
        """#)

        #expect(item.studio == "Universal Pictures")
        #expect(item.originallyAvailableAt == "1963-12-05")
        #expect(item.ratingImage == "imdb://image.rating")
        #expect(item.audienceRatingImage == "rottentomatoes://image.rating.upright")
        #expect(item.guids.map(\.id) == ["imdb://tt0047437", "tmdb://4808"])
        #expect(item.ratings.count == 4)
        #expect(item.ratings[1].value == 8.6)
        #expect(item.writers.map(\.tag) == ["Peter Stone", "Marc Behm"])
        #expect(item.countries.map(\.tag) == ["United States"])
        #expect(item.roles.map(\.role) == ["Peter Joshua", "Regina Lampert"])

        let presentation = PlexMediaMetadataPresentation(
            item: item,
            locale: Locale(identifier: "en_US")
        )

        #expect(presentation.facts == [
            .init(kind: .originalTitle, label: "Original Title", value: "The Unsuspected Wife"),
            .init(kind: .studio, label: "Studio", value: "Universal Pictures"),
            .init(kind: .releaseDate, label: "Released", value: "December 5, 1963"),
            .init(kind: .genres, label: "Genres", value: "Comedy, Mystery"),
            .init(kind: .countries, label: "Country", value: "United States"),
        ])

        #expect(PlexExternalRatingsPresentation(
            item: item,
            locale: Locale(identifier: "en_US")
        ).ratings == [
            .init(
                source: .imdb,
                displayValue: "7.9",
                accessibilityLabel: "IMDb rating, 7.9 out of 10",
                isFresh: nil,
                destinationURL: URL(string: "https://www.imdb.com/title/tt0047437/")
            ),
            .init(
                source: .rottenTomatoes,
                displayValue: "86%",
                accessibilityLabel: "Rotten Tomatoes Tomatometer, 86%",
                isFresh: true,
                destinationURL: nil
            ),
        ])
    }

    @Test func externalRatingsIgnoreAudienceTomatoesTMDBAndGenericRatings() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "ratings-without-approved-sources",
          "title": "Movie",
          "type": "movie",
          "rating": 7.4,
          "ratingImage": "themoviedb://image.rating",
          "audienceRating": 8,
          "audienceRatingImage": "rottentomatoes://image.rating.upright",
          "Rating": [
            { "image": "themoviedb://image.rating", "type": "audience", "value": 7.4 },
            { "image": "rottentomatoes://image.rating.upright", "type": "audience", "value": 8 }
          ]
        }
        """#)

        #expect(PlexExternalRatingsPresentation(item: item).ratings.isEmpty)
        #expect(PlexMediaMetadataPresentation(item: item).facts.isEmpty)
    }

    @Test func imdbRatingsAlwaysShowOneDecimalPlace() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "whole-number-imdb-rating",
          "title": "Episode",
          "type": "episode",
          "Rating": [
            { "image": "imdb://image.rating", "type": "audience", "value": 8 }
          ]
        }
        """#)

        let rating = try #require(PlexExternalRatingsPresentation(
            item: item,
            locale: Locale(identifier: "en_US")
        ).ratings.first)

        #expect(rating.displayValue == "8.0")
        #expect(rating.accessibilityLabel == "IMDb rating, 8.0 out of 10")
    }

    @Test func externalRatingsOmitInvalidScoresAndIdentifyRottenTomatometer() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "mixed-rating-validity",
          "title": "Movie",
          "type": "movie",
          "Rating": [
            { "image": "imdb://image.rating", "type": "audience", "value": 11 },
            { "image": "rottentomatoes://image.rating.ripe", "type": "critic", "value": "5.9" }
          ]
        }
        """#)

        #expect(PlexExternalRatingsPresentation(
            item: item,
            locale: Locale(identifier: "en_US")
        ).ratings == [
            .init(
                source: .rottenTomatoes,
                displayValue: "59%",
                accessibilityLabel: "Rotten Tomatoes Tomatometer, 59%",
                isFresh: false,
                destinationURL: nil
            ),
        ])
    }

    @Test func imdbRatingRejectsMalformedAndNonTitleExternalIdentifiers() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "invalid-imdb-guids",
          "title": "Movie",
          "type": "movie",
          "Guid": [
            { "id": "imdb://nm0000158" },
            { "id": "imdb://tt-not-a-number" },
            { "id": "https://www.imdb.com/title/tt0047437/" }
          ],
          "Rating": [
            { "image": "imdb://image.rating", "type": "audience", "value": 7.9 }
          ]
        }
        """#)

        let rating = try #require(PlexExternalRatingsPresentation(item: item).ratings.first)
        #expect(rating.source == .imdb)
        #expect(rating.destinationURL == nil)
    }

    @Test func usesLabelTerminologyAndPreservesPublishedTimestampPrecision() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "album-1",
          "title": "Album",
          "originalTitle": "album",
          "type": "album",
          "studio": "Record Label",
          "originallyAvailableAt": "2026-08-30 10:15:42",
          "Country": [
            { "tag": "United States" },
            { "tag": "Canada" }
          ]
        }
        """#)

        let presentation = PlexMediaMetadataPresentation(
            item: item,
            locale: Locale(identifier: "en_US")
        )

        #expect(presentation.facts.map(\.kind) == [.studio, .releaseDate, .countries])
        #expect(presentation.facts[0].label == "Label")
        #expect(presentation.facts[0].value == "Record Label")
        #expect(presentation.facts[1].label == "Released")
        #expect(presentation.facts[1].value.contains("August 30, 2026"))
        #expect(presentation.facts[1].value.contains("10:15:42"))
        #expect(presentation.facts[2].label == "Countries")
        #expect(presentation.facts[2].value == "United States, Canada")
    }

    @Test func omitsMalformedDatesOutOfRangeRatingsAndBlankTags() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "bad-contract-values",
          "title": "Movie",
          "type": "movie",
          "originallyAvailableAt": "2026-02-30",
          "rating": 11,
          "audienceRating": -1,
          "Genre": [{ "tag": "   " }],
          "Role": []
        }
        """#)

        #expect(PlexMediaMetadataPresentation(item: item).facts.isEmpty)
    }

    @Test func photoDetailsIncludeExactServerDimensions() throws {
        let item = try decodeItem(#"""
        {
          "ratingKey": "photo-1",
          "title": "Vacation",
          "type": "photo",
          "Media": [{
            "width": "6000",
            "height": "4000",
            "Part": [{ "key": "/library/parts/700/file.jpeg" }]
          }]
        }
        """#)

        #expect(PlexMediaMetadataPresentation(item: item).facts == [
            .init(kind: .dimensions, label: "Dimensions", value: "6,000 × 4,000"),
        ])
    }

    private func decodeItem(_ json: String) throws -> PlexMediaItem {
        try JSONDecoder().decode(PlexMediaItem.self, from: Data(json.utf8))
    }
}
