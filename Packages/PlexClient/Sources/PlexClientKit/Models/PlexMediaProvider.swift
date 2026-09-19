import PlexModels
import Foundation

public struct PlexLibraryProviderEndpoints: Equatable, Sendable {
    public let providerIdentifier: String
    public let browseRoutesByLibraryID: [String: PlexLibraryBrowseRoute]
    public let promotedPath: String?
    public let continueWatchingPath: String?
    public let searchPath: String?
    public let timelinePath: String?
    public let scrobblePath: String?
    public let unscrobblePath: String?
    public let playQueuePath: String?
    public let ratePath: String?
    public let metadataPath: String?
    public let removeFromContinueWatchingPath: String?
    public let collectionPath: String?
    public let playlistPath: String?
    public let playlistReadOnly: Bool?
    public let canManage: Bool
    public let serverAllowsSync: Bool?
    public let supportsDownloadSubscriptions: Bool

    public init(
        providerIdentifier: String,
        browseRoutesByLibraryID: [String: PlexLibraryBrowseRoute] = [:],
        promotedPath: String? = nil,
        continueWatchingPath: String? = nil,
        searchPath: String? = nil,
        timelinePath: String?,
        scrobblePath: String?,
        unscrobblePath: String?,
        playQueuePath: String?,
        ratePath: String?,
        metadataPath: String?,
        removeFromContinueWatchingPath: String?,
        collectionPath: String? = nil,
        playlistPath: String? = nil,
        playlistReadOnly: Bool? = nil,
        canManage: Bool,
        serverAllowsSync: Bool? = nil,
        supportsDownloadSubscriptions: Bool = false
    ) {
        self.providerIdentifier = providerIdentifier
        self.browseRoutesByLibraryID = browseRoutesByLibraryID
        self.promotedPath = promotedPath
        self.continueWatchingPath = continueWatchingPath
        self.searchPath = searchPath
        self.timelinePath = timelinePath
        self.scrobblePath = scrobblePath
        self.unscrobblePath = unscrobblePath
        self.playQueuePath = playQueuePath
        self.ratePath = ratePath
        self.metadataPath = metadataPath
        self.removeFromContinueWatchingPath = removeFromContinueWatchingPath
        self.collectionPath = collectionPath
        self.playlistPath = playlistPath
        self.playlistReadOnly = playlistReadOnly
        self.canManage = canManage
        self.serverAllowsSync = serverAllowsSync
        self.supportsDownloadSubscriptions = supportsDownloadSubscriptions
    }

    public var supportsTimeline: Bool {
        timelinePath != nil
    }

    public func browseRoute(for libraryID: String) -> PlexLibraryBrowseRoute? {
        browseRoutesByLibraryID[libraryID]
    }

    public var supportsWatchedStateMutation: Bool {
        scrobblePath != nil && unscrobblePath != nil
    }

    public var supportsPlayQueues: Bool {
        playQueuePath != nil
    }

    public var supportsRating: Bool {
        ratePath != nil
    }

    public var supportsMetadataRefresh: Bool {
        canManage && metadataPath != nil
    }

    public var supportsRemoveFromContinueWatching: Bool {
        removeFromContinueWatchingPath != nil
    }

    public var supportsCollectionManagement: Bool {
        canManage && collectionPath != nil && metadataPath != nil
    }

    public var supportsPlaylists: Bool {
        playlistPath != nil
    }

    public var supportsPlaylistManagement: Bool {
        supportsPlaylists && playlistReadOnly != true
    }
}

public struct PlexLibraryBrowseRoute: Equatable, Sendable {
    public let sectionPath: String
    public let contentPath: String

    public init(sectionPath: String, contentPath: String) {
        self.sectionPath = sectionPath
        self.contentPath = contentPath
    }
}

public struct PlexMediaProvidersEnvelope: Decodable, Sendable {
    public let mediaContainer: PlexMediaProvidersContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }

    public init(mediaContainer: PlexMediaProvidersContainer) {
        self.mediaContainer = mediaContainer
    }
}

public struct PlexMediaProvidersContainer: Decodable, Sendable {
    public let providers: [PlexMediaProvider]
    public let allowSync: Bool?

    private enum CodingKeys: String, CodingKey {
        case providers = "MediaProvider"
        case allowSync
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        providers = try values.decodeIfPresent([PlexMediaProvider].self, forKey: .providers) ?? []
        allowSync = values.decodePlexBoolIfPresent(forKey: .allowSync)
    }

    public func libraryProviderEndpoints() throws -> PlexLibraryProviderEndpoints {
        guard let provider = providers.first(where: {
            $0.identifier == PlexMediaProvider.libraryIdentifier
        }) else {
            throw PlexAPIError.missingLibraryProvider
        }

        let timeline = provider.features.first(where: {
            $0.type.caseInsensitiveCompare("timeline") == .orderedSame
        })
        let content = provider.features.first(where: {
            $0.type.caseInsensitiveCompare("content") == .orderedSame
        })
        var browseRoutesByLibraryID: [String: PlexLibraryBrowseRoute] = [:]
        for directory in content?.directories ?? [] {
            guard let libraryID = directory.id,
                  let sectionPath = directory.key,
                  let libraryPivot = directory.pivots.first(where: {
                      $0.id.caseInsensitiveCompare("library") == .orderedSame
                          && $0.type.caseInsensitiveCompare("list") == .orderedSame
                  }),
                  let contentPath = libraryPivot.key.nilIfBlank else {
                continue
            }
            guard browseRoutesByLibraryID[libraryID] == nil else {
                throw PlexAPIError.invalidResponse
            }
            browseRoutesByLibraryID[libraryID] = PlexLibraryBrowseRoute(
                sectionPath: sectionPath,
                contentPath: contentPath
            )
        }
        let promotedPath = provider.features.first(where: {
            $0.type.caseInsensitiveCompare("promoted") == .orderedSame
        })?.key?.nilIfBlank
        let continueWatchingPath = provider.features.first(where: {
            $0.type.caseInsensitiveCompare("continuewatching") == .orderedSame
        })?.key?.nilIfBlank
        let searchPath = provider.features.first(where: {
            $0.type.caseInsensitiveCompare("search") == .orderedSame
        })?.key?.nilIfBlank
        let timelinePath = timeline?.key?.nilIfBlank
        let scrobblePath = timeline?.scrobbleKey?.nilIfBlank
        let unscrobblePath = timeline?.unscrobbleKey?.nilIfBlank
        let ratePath = provider.features.first(where: {
            $0.type.caseInsensitiveCompare("rate") == .orderedSame
        })?.key?.nilIfBlank
        let playQueuePath = provider.features.first(where: {
            $0.type.caseInsensitiveCompare("playqueue") == .orderedSame
        })?.key?.nilIfBlank
        let metadataPath = provider.features.first(where: {
            $0.type.caseInsensitiveCompare("metadata") == .orderedSame
        })?.key?.nilIfBlank
        let removeFromContinueWatchingPath = provider.features.first(where: {
            $0.type.caseInsensitiveCompare("actions") == .orderedSame
        })?.actions.first(where: {
            $0.id.caseInsensitiveCompare("removeFromContinueWatching") == .orderedSame
        })?.key.nilIfBlank
        let collectionPath = provider.features.first(where: {
            $0.type.caseInsensitiveCompare("collection") == .orderedSame
        })?.key?.nilIfBlank
        let playlist = provider.features.first(where: {
            $0.type.caseInsensitiveCompare("playlist") == .orderedSame
        })
        let playlistPath = playlist?.key?.nilIfBlank
        let playlistReadOnly = playlist?.readOnly
        let canManage = provider.features.contains {
            $0.type.caseInsensitiveCompare("manage") == .orderedSame
        }
        let supportsDownloadSubscriptions = provider.features.contains {
            $0.type.caseInsensitiveCompare("subscribe") == .orderedSame
                && $0.flavor?.caseInsensitiveCompare("download") == .orderedSame
        }

        return PlexLibraryProviderEndpoints(
            providerIdentifier: provider.identifier,
            browseRoutesByLibraryID: browseRoutesByLibraryID,
            promotedPath: promotedPath,
            continueWatchingPath: continueWatchingPath,
            searchPath: searchPath,
            timelinePath: timelinePath,
            scrobblePath: scrobblePath,
            unscrobblePath: unscrobblePath,
            playQueuePath: playQueuePath,
            ratePath: ratePath,
            metadataPath: metadataPath,
            removeFromContinueWatchingPath: removeFromContinueWatchingPath,
            collectionPath: collectionPath,
            playlistPath: playlistPath,
            playlistReadOnly: playlistReadOnly,
            canManage: canManage,
            serverAllowsSync: allowSync,
            supportsDownloadSubscriptions: supportsDownloadSubscriptions
        )
    }
}

public struct PlexMediaProvider: Decodable, Sendable {
    public static let libraryIdentifier = "com.plexapp.plugins.library"

    public let identifier: String
    public let features: [PlexMediaProviderFeature]

    private enum CodingKeys: String, CodingKey {
        case identifier
        case features = "Feature"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try values.decode(String.self, forKey: .identifier)
        features = try values.decodeIfPresent([PlexMediaProviderFeature].self, forKey: .features) ?? []
    }
}

public struct PlexMediaProviderFeature: Decodable, Sendable {
    public let type: String
    public let flavor: String?
    public let key: String?
    public let scrobbleKey: String?
    public let unscrobbleKey: String?
    public let readOnly: Bool?
    public let actions: [PlexMediaProviderAction]
    public let directories: [PlexMediaProviderDirectory]

    private enum CodingKeys: String, CodingKey {
        case type
        case flavor
        case key
        case scrobbleKey
        case unscrobbleKey
        case readOnly
        case readonly
        case actions = "Action"
        case directories = "Directory"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        type = try values.decode(String.self, forKey: .type)
        flavor = try values.decodeIfPresent(String.self, forKey: .flavor)
        key = try values.decodeIfPresent(String.self, forKey: .key)
        scrobbleKey = try values.decodeIfPresent(String.self, forKey: .scrobbleKey)
        unscrobbleKey = try values.decodeIfPresent(String.self, forKey: .unscrobbleKey)
        readOnly = values.decodePlexBoolIfPresent(forKey: .readOnly)
            ?? values.decodePlexBoolIfPresent(forKey: .readonly)
        actions = try values.decodeIfPresent([PlexMediaProviderAction].self, forKey: .actions) ?? []
        directories = try values.decodeIfPresent(
            [PlexMediaProviderDirectory].self,
            forKey: .directories
        ) ?? []
    }
}

public struct PlexMediaProviderDirectory: Decodable, Sendable {
    public let id: String?
    public let key: String?
    public let pivots: [PlexMediaProviderPivot]

    private enum CodingKeys: String, CodingKey {
        case id
        case key
        case pivots = "Pivot"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = values.decodePlexStringIfPresent(forKey: .id)?.nilIfBlank
        key = try values.decodeIfPresent(String.self, forKey: .key)?.nilIfBlank
        pivots = try values.decodeIfPresent([PlexMediaProviderPivot].self, forKey: .pivots) ?? []
    }
}

public struct PlexMediaProviderPivot: Decodable, Sendable {
    public let id: String
    public let key: String
    public let type: String

    public init(id: String, key: String, type: String) {
        self.id = id
        self.key = key
        self.type = type
    }
}

public struct PlexMediaProviderAction: Decodable, Sendable {
    public let id: String
    public let key: String

    public init(id: String, key: String) {
        self.id = id
        self.key = key
    }
}
