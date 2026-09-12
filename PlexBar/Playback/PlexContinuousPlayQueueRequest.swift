import Foundation

struct PlexCinemaPlayQueueRequest: Equatable, Sendable {
    let itemKey: String
    let sourceURI: String
    let extrasPrefixCount: Int

    init(
        item: PlexMediaItem,
        extrasPrefixCount: Int,
        serverIdentifier: String,
        providerIdentifier: String = PlexMediaProvider.libraryIdentifier
    ) throws {
        guard item.type?.lowercased() == "movie",
              (0...5).contains(extrasPrefixCount),
              let itemKey = item.key?.nilIfBlank,
              itemKey.hasPrefix("/") else {
            throw PlexAPIError.invalidPlayQueue
        }
        self.itemKey = itemKey
        self.extrasPrefixCount = extrasPrefixCount
        sourceURI = try PlexMediaSourceURI.item(
            item,
            serverIdentifier: serverIdentifier,
            providerIdentifier: providerIdentifier
        )
    }

    var queryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "uri", value: sourceURI),
            URLQueryItem(name: "type", value: PlexContinuousPlayQueueType.video.rawValue),
            URLQueryItem(name: "key", value: itemKey),
            URLQueryItem(name: "shuffle", value: "0"),
            URLQueryItem(name: "repeat", value: "0"),
            URLQueryItem(name: "continuous", value: "0"),
            URLQueryItem(name: "extrasPrefixCount", value: String(extrasPrefixCount)),
        ]
    }
}

struct PlexContinuousPlayQueueRequest: Equatable, Sendable {
    let itemKey: String
    let queueType: PlexContinuousPlayQueueType
    let sourceURI: String
    let usesOnDeck: Bool

    init(
        item: PlexMediaItem,
        serverIdentifier: String,
        providerIdentifier: String = PlexMediaProvider.libraryIdentifier
    ) throws {
        guard let queueType = item.continuousPlayQueueType,
              let itemKey = item.key?.nilIfBlank,
              itemKey.hasPrefix("/") else {
            throw PlexAPIError.invalidPlayQueue
        }
        self.itemKey = itemKey
        self.queueType = queueType
        sourceURI = try PlexMediaSourceURI.item(
            item,
            serverIdentifier: serverIdentifier,
            providerIdentifier: providerIdentifier
        )
        usesOnDeck = item.continuousPlayQueueUsesOnDeck
    }

    var queryItems: [URLQueryItem] {
        var values = [
            URLQueryItem(name: "uri", value: sourceURI),
            URLQueryItem(name: "type", value: queueType.rawValue),
            URLQueryItem(name: "shuffle", value: "0"),
            URLQueryItem(name: "repeat", value: "0"),
            URLQueryItem(name: "continuous", value: "1"),
        ]
        values.append(
            URLQueryItem(
                name: usesOnDeck ? "onDeck" : "key",
                value: usesOnDeck ? "1" : itemKey
            )
        )
        return values
    }
}

enum PlexPlayQueueMutation: Equatable, Sendable {
    case shuffled(Bool)
    case reset

    fileprivate var endpointComponent: String {
        switch self {
        case .shuffled(true): "shuffle"
        case .shuffled(false): "unshuffle"
        case .reset: "reset"
        }
    }
}

struct PlexPlayQueueMutationRequest: Equatable, Sendable {
    let queueID: Int
    let mutation: PlexPlayQueueMutation

    init(queueID: Int, mutation: PlexPlayQueueMutation) throws {
        guard queueID > 0 else {
            throw PlexAPIError.invalidPlayQueue
        }
        self.queueID = queueID
        self.mutation = mutation
    }

    var endpointPathComponents: [String] {
        [String(queueID), mutation.endpointComponent]
    }
}

enum PlexPlayQueueItemMutation: Equatable, Sendable {
    case remove(playQueueItemID: String)
    case move(PlexPlayQueueItemMove)
}

struct PlexPlayQueueItemMutationRequest: Equatable, Sendable {
    let queueID: Int
    let mutation: PlexPlayQueueItemMutation

    init(queueID: Int, mutation: PlexPlayQueueItemMutation) throws {
        guard queueID > 0 else {
            throw PlexAPIError.invalidPlayQueue
        }
        switch mutation {
        case .remove(let playQueueItemID):
            guard Self.isValidIdentifier(playQueueItemID) else {
                throw PlexAPIError.invalidPlayQueue
            }
        case .move(let move):
            guard Self.isValidIdentifier(move.playQueueItemID),
                  Self.isValidIdentifier(move.afterPlayQueueItemID),
                  move.playQueueItemID != move.afterPlayQueueItemID else {
                throw PlexAPIError.invalidPlayQueue
            }
        }
        self.queueID = queueID
        self.mutation = mutation
    }

    var endpointPathComponents: [String] {
        switch mutation {
        case .remove(let playQueueItemID):
            [String(queueID), "items", playQueueItemID]
        case .move(let move):
            [String(queueID), "items", move.playQueueItemID, "move"]
        }
    }

    var method: String {
        switch mutation {
        case .remove: "DELETE"
        case .move: "PUT"
        }
    }

    var queryItems: [URLQueryItem] {
        switch mutation {
        case .remove:
            []
        case .move(let move):
            [URLQueryItem(name: "after", value: move.afterPlayQueueItemID)]
        }
    }

    private static func isValidIdentifier(_ identifier: String) -> Bool {
        guard let identifier = identifier.nilIfBlank else {
            return false
        }
        return identifier.utf8.allSatisfy { (48...57).contains($0) }
    }
}
