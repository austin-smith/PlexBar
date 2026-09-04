import Foundation

struct PlexMediaMetadataFact: Equatable, Identifiable, Sendable {
    enum Kind: String, Sendable {
        case originalTitle
        case studio
        case releaseDate
        case dimensions
        case genres
        case countries
    }

    let kind: Kind
    let label: String
    let value: String

    var id: Kind { kind }
}

struct PlexMediaMetadataPresentation: Equatable, Sendable {
    let facts: [PlexMediaMetadataFact]

    init(item: PlexMediaItem, locale: Locale = .autoupdatingCurrent) {
        var facts: [PlexMediaMetadataFact] = []

        if let originalTitle = item.originalTitle?.nilIfBlank,
           originalTitle.caseInsensitiveCompare(item.title) != .orderedSame {
            facts.append(.init(kind: .originalTitle, label: "Original Title", value: originalTitle))
        }

        if let studio = item.studio?.nilIfBlank {
            facts.append(.init(kind: .studio, label: item.studioLabel, value: studio))
        }

        if let releaseDate = Self.formattedReleaseDate(item.originallyAvailableAt, locale: locale) {
            facts.append(.init(kind: .releaseDate, label: "Released", value: releaseDate))
        }

        if let dimensions = PlexPhotoPresentation(item: item)?.dimensionsText {
            facts.append(.init(kind: .dimensions, label: "Dimensions", value: dimensions))
        }

        Self.appendTags(
            item.genres,
            singularLabel: "Genre",
            pluralLabel: "Genres",
            kind: .genres,
            to: &facts
        )
        Self.appendTags(
            item.countries,
            singularLabel: "Country",
            pluralLabel: "Countries",
            kind: .countries,
            to: &facts
        )

        self.facts = facts
    }

    private static func appendTags(
        _ tags: [PlexTag],
        singularLabel: String,
        pluralLabel: String,
        kind: PlexMediaMetadataFact.Kind,
        to facts: inout [PlexMediaMetadataFact]
    ) {
        let values = uniqueValues(tags.compactMap { $0.tag.nilIfBlank })
        guard !values.isEmpty else {
            return
        }

        facts.append(.init(
            kind: kind,
            label: values.count == 1 ? singularLabel : pluralLabel,
            value: values.joined(separator: ", ")
        ))
    }

    private static func uniqueValues(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    private static func formattedReleaseDate(_ value: String?, locale: Locale) -> String? {
        guard let value = value?.nilIfBlank,
              let timestamp = PlexReleaseTimestamp(value) else {
            return nil
        }

        let style = Date.FormatStyle(
            date: .long,
            time: timestamp.includesTime ? .standard : .omitted,
            locale: locale,
            calendar: Calendar(identifier: .gregorian),
            timeZone: timestamp.timeZone
        )
        return timestamp.date.formatted(style)
    }
}

private extension PlexMediaItem {
    var studioLabel: String {
        switch type?.lowercased() {
        case "artist", "album", "track": "Label"
        default: "Studio"
        }
    }
}

private struct PlexReleaseTimestamp {
    let date: Date
    let includesTime: Bool
    let timeZone: TimeZone

    init?(_ value: String) {
        let segments = value.split(separator: " ", omittingEmptySubsequences: false)
        guard segments.count == 1 || segments.count == 2,
              let dateComponents = Self.parse(
                  segments[0],
                  separator: "-",
                  componentWidths: [4, 2, 2]
              ) else {
            return nil
        }

        let timeComponents: [Int]
        if segments.count == 2 {
            guard let parsedTime = Self.parse(
                segments[1],
                separator: ":",
                componentWidths: [2, 2, 2]
            ) else {
                return nil
            }
            timeComponents = parsedTime
        } else {
            timeComponents = [0, 0, 0]
        }

        guard (0...23).contains(timeComponents[0]),
              (0...59).contains(timeComponents[1]),
              (0...59).contains(timeComponents[2]),
              let timeZone = TimeZone(secondsFromGMT: 0) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let expected = DateComponents(
            timeZone: timeZone,
            year: dateComponents[0],
            month: dateComponents[1],
            day: dateComponents[2],
            hour: timeComponents[0],
            minute: timeComponents[1],
            second: timeComponents[2]
        )
        guard let date = calendar.date(from: expected) else {
            return nil
        }

        let actual = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        guard actual.year == expected.year,
              actual.month == expected.month,
              actual.day == expected.day,
              actual.hour == expected.hour,
              actual.minute == expected.minute,
              actual.second == expected.second else {
            return nil
        }

        self.date = date
        includesTime = segments.count == 2
        self.timeZone = timeZone
    }

    private static func parse(
        _ value: Substring,
        separator: Character,
        componentWidths: [Int]
    ) -> [Int]? {
        let components = value.split(separator: separator, omittingEmptySubsequences: false)
        guard components.count == componentWidths.count else {
            return nil
        }

        var values: [Int] = []
        for (component, width) in zip(components, componentWidths) {
            guard component.count == width,
                  component.allSatisfy(\.isNumber),
                  let integer = Int(component) else {
                return nil
            }
            values.append(integer)
        }
        return values
    }
}
