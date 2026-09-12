import Foundation

struct PlexLibraryProviderEndpoints: Equatable, Sendable {
    let providerIdentifier: String
    let browseRoutesByLibraryID: [String: PlexLibraryBrowseRoute]
    let promotedPath: String?
    let continueWatchingPath: String?
    let searchPath: String?
    let timelinePath: String?
    let scrobblePath: String?
    let unscrobblePath: String?
    let playQueuePath: String?
    let ratePath: String?
    let metadataPath: String?
    let removeFromContinueWatchingPath: String?
    let collectionPath: String?
    let playlistPath: String?
    let playlistReadOnly: Bool?
    let canManage: Bool
    let serverAllowsSync: Bool?
    let supportsDownloadSubscriptions: Bool

    init(
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

    var supportsTimeline: Bool {
        timelinePath != nil
    }

    func browseRoute(for libraryID: String) -> PlexLibraryBrowseRoute? {
        browseRoutesByLibraryID[libraryID]
    }

    var supportsWatchedStateMutation: Bool {
        scrobblePath != nil && unscrobblePath != nil
    }

    var supportsPlayQueues: Bool {
        playQueuePath != nil
    }

    var supportsRating: Bool {
        ratePath != nil
    }

    var supportsMetadataRefresh: Bool {
        canManage && metadataPath != nil
    }

    var supportsRemoveFromContinueWatching: Bool {
        removeFromContinueWatchingPath != nil
    }

    var supportsCollectionManagement: Bool {
        canManage && collectionPath != nil && metadataPath != nil
    }

    var supportsPlaylists: Bool {
        playlistPath != nil
    }

    var supportsPlaylistManagement: Bool {
        supportsPlaylists && playlistReadOnly != true
    }
}

struct PlexLibraryBrowseRoute: Equatable, Sendable {
    let sectionPath: String
    let contentPath: String
}

struct PlexMediaProvidersEnvelope: Decodable, Sendable {
    let mediaContainer: PlexMediaProvidersContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexMediaProvidersContainer: Decodable, Sendable {
    let providers: [PlexMediaProvider]
    let allowSync: Bool?

    enum CodingKeys: String, CodingKey {
        case providers = "MediaProvider"
        case allowSync
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        providers = try values.decodeIfPresent([PlexMediaProvider].self, forKey: .providers) ?? []
        allowSync = values.decodePlexBoolIfPresent(forKey: .allowSync)
    }

    func libraryProviderEndpoints() throws -> PlexLibraryProviderEndpoints {
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

struct PlexMediaProvider: Decodable, Sendable {
    static let libraryIdentifier = "com.plexapp.plugins.library"

    let identifier: String
    let features: [PlexMediaProviderFeature]

    enum CodingKeys: String, CodingKey {
        case identifier
        case features = "Feature"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try values.decode(String.self, forKey: .identifier)
        features = try values.decodeIfPresent([PlexMediaProviderFeature].self, forKey: .features) ?? []
    }
}

struct PlexMediaProviderFeature: Decodable, Sendable {
    let type: String
    let flavor: String?
    let key: String?
    let scrobbleKey: String?
    let unscrobbleKey: String?
    let readOnly: Bool?
    let actions: [PlexMediaProviderAction]
    let directories: [PlexMediaProviderDirectory]

    enum CodingKeys: String, CodingKey {
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

    init(from decoder: Decoder) throws {
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

struct PlexMediaProviderDirectory: Decodable, Sendable {
    let id: String?
    let key: String?
    let pivots: [PlexMediaProviderPivot]

    private enum CodingKeys: String, CodingKey {
        case id
        case key
        case pivots = "Pivot"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = values.decodePlexStringIfPresent(forKey: .id)?.nilIfBlank
        key = try values.decodeIfPresent(String.self, forKey: .key)?.nilIfBlank
        pivots = try values.decodeIfPresent([PlexMediaProviderPivot].self, forKey: .pivots) ?? []
    }
}

struct PlexMediaProviderPivot: Decodable, Sendable {
    let id: String
    let key: String
    let type: String
}

struct PlexMediaProviderAction: Decodable, Sendable {
    let id: String
    let key: String
}
