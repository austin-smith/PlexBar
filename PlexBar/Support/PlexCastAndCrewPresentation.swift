import Foundation

extension PlexMediaItem {
    /// Episodes inherit series credits only when Plex has no episode-specific cast.
    var episodeSeriesCastRatingKey: String? {
        guard type?.caseInsensitiveCompare("episode") == .orderedSame,
              roles.isEmpty,
              let seriesRatingKey = grandparentRatingKey?.nilIfBlank,
              seriesRatingKey != ratingKey else { return nil }
        return seriesRatingKey
    }
}

struct PlexCastAndCrewCredit: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    let thumb: String?
    let route: PlexPersonRoute?
}

struct PlexCastAndCrewPresentation: Equatable, Sendable {
    let cast: [PlexCastAndCrewCredit]
    let crew: [PlexCastAndCrewCredit]

    var isEmpty: Bool {
        cast.isEmpty && crew.isEmpty
    }

    init(item: PlexMediaItem, episodeSeriesCast: [PlexTag] = []) {
        var crewCollector = CreditCollector(scope: "crew")
        crewCollector.append(item.directors) { _ in "Director" }
        crewCollector.append(item.writers) { _ in "Writer" }
        crewCollector.append(item.producers) { _ in "Producer" }
        crew = crewCollector.credits

        var castCollector = CreditCollector(scope: "cast")
        let castPeople = item.roles.isEmpty ? episodeSeriesCast : item.roles
        castCollector.append(
            castPeople.enumerated()
                .sorted { left, right in
                    let leftOrder = left.element.order ?? Int.max
                    let rightOrder = right.element.order ?? Int.max
                    return leftOrder == rightOrder ? left.offset < right.offset : leftOrder < rightOrder
                }
                .map(\.element)
        ) { $0.role?.nilIfBlank ?? "Cast" }
        cast = castCollector.credits
    }
}

private struct CreditCollector {
    let scope: String
    private var builders: [CreditBuilder] = []
    private var indexByIdentity: [String: Int] = [:]

    init(scope: String) {
        self.scope = scope
    }

    mutating func append(_ people: [PlexTag], credit: (PlexTag) -> String) {
        for (position, person) in people.enumerated() {
            guard let name = person.tag.nilIfBlank else {
                continue
            }
            let subtitle = credit(person)
            let exactIdentity = person.tagKey?.nilIfBlank.map { "tag-key:\($0)" }
                ?? person.id.map { "id:\($0)" }

            if let exactIdentity, let existingIndex = indexByIdentity[exactIdentity] {
                builders[existingIndex].appendCredit(subtitle)
                builders[existingIndex].fillMissingPortrait(person.thumb)
                continue
            }

            let identity = exactIdentity
                ?? "anonymous:\(builders.count):\(position):\(name):\(subtitle)"
            indexByIdentity[identity] = builders.count
            builders.append(CreditBuilder(
                id: "\(scope):\(identity)",
                person: person,
                name: name,
                credit: subtitle
            ))
        }
    }

    var credits: [PlexCastAndCrewCredit] {
        builders.map(\.credit)
    }
}

private struct CreditBuilder {
    let id: String
    var person: PlexTag
    let name: String
    private var creditLabels: [String]

    init(id: String, person: PlexTag, name: String, credit: String) {
        self.id = id
        self.person = person
        self.name = name
        creditLabels = [credit]
    }

    mutating func appendCredit(_ credit: String) {
        guard !creditLabels.contains(credit) else {
            return
        }
        creditLabels.append(credit)
    }

    mutating func fillMissingPortrait(_ thumb: String?) {
        guard person.thumb?.nilIfBlank == nil, thumb?.nilIfBlank != nil else {
            return
        }
        person = PlexTag.copying(person, thumb: thumb)
    }

    var credit: PlexCastAndCrewCredit {
        let subtitle = creditLabels.joined(separator: " · ")
        return PlexCastAndCrewCredit(
            id: id,
            name: name,
            subtitle: subtitle,
            thumb: person.thumb?.nilIfBlank,
            route: PlexPersonRoute(person: person)
        )
    }
}

private extension PlexTag {
    static func copying(_ person: PlexTag, thumb: String?) -> PlexTag {
        PlexTag(
            id: person.id,
            tag: person.tag,
            tagKey: person.tagKey,
            tagType: person.tagType,
            filter: person.filter,
            role: person.role,
            thumb: thumb,
            order: person.order
        )
    }
}
