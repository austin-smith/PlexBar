import Foundation

struct PlexDownloadAuthorization: Equatable, Sendable {
    let accountHasDownloadsEntitlement: Bool
    let serverAllowsSync: Bool?
    let libraryAllowsSync: Bool?
    let libraryProviderSupportsDownloads: Bool

    init(
        user: PlexAuthenticatedUser,
        library: PlexLibrary,
        providerEndpoints: PlexLibraryProviderEndpoints
    ) {
        accountHasDownloadsEntitlement = user.hasDownloadsAccountEntitlement
        serverAllowsSync = providerEndpoints.serverAllowsSync
        libraryAllowsSync = library.allowSync
        libraryProviderSupportsDownloads = providerEndpoints.supportsDownloadSubscriptions
    }

    var isAuthorized: Bool {
        accountHasDownloadsEntitlement
            && serverAllowsSync == true
            && libraryAllowsSync == true
            && libraryProviderSupportsDownloads
    }
}

struct PlexDownloadAuthorizationScope: Equatable, Sendable {
    let accountID: Int
    let serverIdentifier: String
    let serverURL: URL
    let libraryID: String
    let providerIdentifier: String
}

struct PlexDownloadCreationAuthorization: Equatable, Sendable {
    let scope: PlexDownloadAuthorizationScope
    let facts: PlexDownloadAuthorization
}

enum PlexDownloadCreationAuthorizationError: LocalizedError, Equatable {
    case signedOut
    case missingServerIdentity
    case unavailableLibrary
    case accountNotEntitled
    case serverDisallowsDownloads
    case libraryDisallowsDownloads
    case providerDisallowsDownloads
    case authorizationExpired
    case mismatchedTransfer

    var errorDescription: String? {
        switch self {
        case .signedOut:
            "Sign in to Plex before creating a download."
        case .missingServerIdentity:
            "Plex did not provide the selected server identity required for this download."
        case .unavailableLibrary:
            "The selected Plex library is no longer available."
        case .accountNotEntitled:
            "The current Plex account does not include Downloads."
        case .serverDisallowsDownloads:
            "The selected Plex server does not allow Downloads."
        case .libraryDisallowsDownloads:
            "The selected Plex library does not allow Downloads."
        case .providerDisallowsDownloads:
            "The selected Plex provider does not advertise Downloads."
        case .authorizationExpired:
            "The Plex account, server, or library changed before the download could start."
        case .mismatchedTransfer:
            "The prepared download does not belong to the authorized Plex server and library."
        }
    }
}
