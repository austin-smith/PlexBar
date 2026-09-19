import PlexModels
import Foundation

public struct PlexMediaRoute: Hashable, Sendable {
    public let itemID: String
    public let ratingKey: String

    public init(item: PlexMediaItem) {
        itemID = item.id
        ratingKey = item.ratingKey
    }

    public init?(ratingKey: String?) {
        guard let ratingKey = ratingKey?.nilIfBlank else {
            return nil
        }

        itemID = ratingKey
        self.ratingKey = ratingKey
    }

    public func matches(_ item: PlexMediaItem) -> Bool {
        item.id == itemID && item.ratingKey == ratingKey
    }
}

public struct PlexMediaHierarchyDestination: Hashable, Identifiable, Sendable {
    public let relationship: Relationship
    public let title: String
    public let route: PlexMediaRoute

    public var id: String {
        route.ratingKey
    }

    public enum Relationship: String, Hashable, Sendable {
        case show = "Show"
        case season = "Season"
        case artist = "Artist"
        case album = "Album"
    }

    public init(relationship: Relationship, title: String, route: PlexMediaRoute) {
        self.relationship = relationship
        self.title = title
        self.route = route
    }
}

extension PlexMediaItem {
    public var hierarchyDestinations: [PlexMediaHierarchyDestination] {
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

public struct PlexHomeHubRoute: Hashable, Sendable {
    public let hubID: String

    public init(hub: PlexHub) {
        hubID = hub.id
    }

    public func matches(_ hub: PlexHub) -> Bool {
        hub.id == hubID
    }
}

public struct PlexSearchHubRoute: Hashable, Sendable {
    public let query: String
    public let hubID: String
    public let hubKey: String

    public init?(hub: PlexHub, query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let hubKey = hub.key,
              !hubKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        self.query = query
        hubID = hub.id
        self.hubKey = hubKey
    }

    public func matches(_ hub: PlexHub, query: String) -> Bool {
        self.query == query && hub.id == hubID && hub.key == hubKey
    }
}

public struct PlexRelatedHubRoute: Hashable, Sendable {
    public let sourceRatingKey: String
    public let hubID: String
    public let hubKey: String

    public init?(sourceItem: PlexMediaItem, hub: PlexHub) {
        self.init(sourceRatingKey: sourceItem.ratingKey, hub: hub)
    }

    public init?(sourceRatingKey: String, hub: PlexHub) {
        guard let hubKey = hub.key,
              !hubKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        self.sourceRatingKey = sourceRatingKey
        hubID = hub.id
        self.hubKey = hubKey
    }

    public func matches(sourceRatingKey: String, hub: PlexHub) -> Bool {
        self.sourceRatingKey == sourceRatingKey
            && hub.id == hubID
            && hub.key == hubKey
    }
}

public struct PlexPersonRoute: Hashable, Sendable {
    public let identifier: String
    public let name: String
    public let thumb: String?

    public init?(person: PlexTag) {
        guard let identifier = person.tagKey?.nilIfBlank ?? person.id.map(String.init),
              let name = person.tag.nilIfBlank else {
            return nil
        }

        self.identifier = identifier
        self.name = name
        thumb = person.thumb?.nilIfBlank
    }
}

public enum PlexNavigationRoute: Hashable, Sendable {
    case media(PlexMediaRoute)
    case person(PlexPersonRoute)
    case homeHub(PlexHomeHubRoute)
    case searchHub(PlexSearchHubRoute)
    case relatedHub(PlexRelatedHubRoute)
}
