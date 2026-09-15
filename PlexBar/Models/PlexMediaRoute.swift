import PlexModels
import Foundation

struct PlexMediaRoute: Hashable, Sendable {
    let itemID: String
    let ratingKey: String

    init(item: PlexMediaItem) {
        itemID = item.id
        ratingKey = item.ratingKey
    }

    init?(ratingKey: String?) {
        guard let ratingKey = ratingKey?.nilIfBlank else {
            return nil
        }

        itemID = ratingKey
        self.ratingKey = ratingKey
    }

    func matches(_ item: PlexMediaItem) -> Bool {
        item.id == itemID && item.ratingKey == ratingKey
    }
}

struct PlexMediaHierarchyDestination: Hashable, Identifiable, Sendable {
    let relationship: Relationship
    let title: String
    let route: PlexMediaRoute

    var id: String {
        route.ratingKey
    }

    enum Relationship: String, Hashable, Sendable {
        case show = "Show"
        case season = "Season"
        case artist = "Artist"
        case album = "Album"
    }
}

extension PlexMediaItem {
    var hierarchyDestinations: [PlexMediaHierarchyDestination] {
        let candidates: [(PlexMediaHierarchyDestination.Relationship, String?, String?)] = switch type?.lowercased() {
        case "episode":
            if skipParent == true {
                [(.show, grandparentTitle, grandparentRatingKey)]
            } else {
                [(.show, grandparentTitle, grandparentRatingKey), (.season, parentTitle, parentRatingKey)]
            }
        case "season":
            [(.show, parentTitle, parentRatingKey)]
        case "track":
            [(.artist, grandparentTitle, grandparentRatingKey), (.album, parentTitle, parentRatingKey)]
        case "album":
            [(.artist, parentTitle, parentRatingKey)]
        default:
            []
        }

        var seenRatingKeys: Set<String> = []
        return candidates.compactMap { relationship, title, ratingKey in
            guard let title = title?.nilIfBlank,
                  let route = PlexMediaRoute(ratingKey: ratingKey),
                  route.ratingKey != self.ratingKey,
                  seenRatingKeys.insert(route.ratingKey).inserted else {
                return nil
            }
            return PlexMediaHierarchyDestination(
                relationship: relationship,
                title: title,
                route: route
            )
        }
    }
}

struct PlexHomeHubRoute: Hashable, Sendable {
    let hubID: String

    init(hub: PlexHub) {
        hubID = hub.id
    }

    func matches(_ hub: PlexHub) -> Bool {
        hub.id == hubID
    }
}

struct PlexSearchHubRoute: Hashable, Sendable {
    let query: String
    let hubID: String
    let hubKey: String

    init?(hub: PlexHub, query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let hubKey = hub.key,
              !hubKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        self.query = query
        hubID = hub.id
        self.hubKey = hubKey
    }

    func matches(_ hub: PlexHub, query: String) -> Bool {
        self.query == query && hub.id == hubID && hub.key == hubKey
    }
}

struct PlexRelatedHubRoute: Hashable, Sendable {
    let sourceRatingKey: String
    let hubID: String
    let hubKey: String

    init?(sourceItem: PlexMediaItem, hub: PlexHub) {
        self.init(sourceRatingKey: sourceItem.ratingKey, hub: hub)
    }

    init?(sourceRatingKey: String, hub: PlexHub) {
        guard let hubKey = hub.key,
              !hubKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        self.sourceRatingKey = sourceRatingKey
        hubID = hub.id
        self.hubKey = hubKey
    }

    func matches(sourceRatingKey: String, hub: PlexHub) -> Bool {
        self.sourceRatingKey == sourceRatingKey
            && hub.id == hubID
            && hub.key == hubKey
    }
}

struct PlexPersonRoute: Hashable, Sendable {
    let identifier: String
    let name: String
    let thumb: String?

    init?(person: PlexTag) {
        guard let identifier = person.tagKey?.nilIfBlank ?? person.id.map(String.init),
              let name = person.tag.nilIfBlank else {
            return nil
        }

        self.identifier = identifier
        self.name = name
        thumb = person.thumb?.nilIfBlank
    }
}

enum PlexNavigationRoute: Hashable, Sendable {
    case media(PlexMediaRoute)
    case person(PlexPersonRoute)
    case homeHub(PlexHomeHubRoute)
    case searchHub(PlexSearchHubRoute)
    case relatedHub(PlexRelatedHubRoute)
}
