import PlexModels
import Foundation

struct PlexExternalRatingPresentation: Equatable, Identifiable, Sendable {
    enum Source: String, Sendable {
        case imdb
        case rottenTomatoes
    }

    let source: Source
    let displayValue: String
    let accessibilityLabel: String
    let isFresh: Bool?
    let destinationURL: URL?

    var id: Source { source }
}

struct PlexExternalRatingsPresentation: Equatable, Sendable {
    let ratings: [PlexExternalRatingPresentation]

    init(item: PlexMediaItem, locale: Locale = .autoupdatingCurrent) {
        ratings = [
            Self.imdbRating(in: item.ratings, guids: item.guids, locale: locale),
            Self.tomatometerRating(in: item.ratings, locale: locale),
        ].compactMap { $0 }
    }

    private static func imdbRating(
        in ratings: [PlexMediaRating],
        guids: [PlexMediaGUID],
        locale: Locale
    ) -> PlexExternalRatingPresentation? {
        guard let rating = ratings.first(where: {
            provider(from: $0.image) == "imdb"
        }), let value = validValue(rating.value) else {
            return nil
        }

        let displayValue = value.formatted(
            .number.locale(locale).precision(.fractionLength(1))
        )
        return .init(
            source: .imdb,
            displayValue: displayValue,
            accessibilityLabel: "IMDb rating, \(displayValue) out of 10",
            isFresh: nil,
            destinationURL: imdbDestinationURL(in: guids)
        )
    }

    private static func tomatometerRating(
        in ratings: [PlexMediaRating],
        locale: Locale
    ) -> PlexExternalRatingPresentation? {
        guard let rating = ratings.first(where: {
            provider(from: $0.image) == "rottentomatoes"
                && $0.type?.caseInsensitiveCompare("critic") == .orderedSame
        }), let value = validValue(rating.value) else {
            return nil
        }

        let displayValue = (value / 10).formatted(
            .percent.locale(locale).precision(.fractionLength(0))
        )
        return .init(
            source: .rottenTomatoes,
            displayValue: displayValue,
            accessibilityLabel: "Rotten Tomatoes Tomatometer, \(displayValue)",
            isFresh: value >= 6,
            destinationURL: nil
        )
    }

    private static func imdbDestinationURL(in guids: [PlexMediaGUID]) -> URL? {
        let identifier = guids.lazy
            .compactMap { imdbTitleIdentifier(from: $0.id) }
            .first
        guard let identifier else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.imdb.com"
        components.path = "/title/\(identifier)/"
        return components.url
    }

    private static func imdbTitleIdentifier(from guid: String) -> String? {
        guard let components = URLComponents(string: guid),
              components.scheme?.caseInsensitiveCompare("imdb") == .orderedSame,
              let identifier = components.host,
              identifier.hasPrefix("tt"),
              identifier.count >= 9,
              identifier.dropFirst(2).allSatisfy(\.isNumber) else {
            return nil
        }

        return identifier
    }

    private static func validValue(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0...10).contains(value) else {
            return nil
        }
        return value
    }

    private static func provider(from image: String?) -> String? {
        guard let image = image?.nilIfBlank,
              let provider = image.split(separator: ":", maxSplits: 1).first else {
            return nil
        }
        return provider.lowercased()
    }
}
