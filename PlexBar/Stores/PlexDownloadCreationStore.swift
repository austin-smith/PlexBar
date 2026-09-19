import PlexClientKit
import PlexModels
import Foundation

@MainActor
final class PlexDownloadCreationStore {
    private let authStore: PlexAuthStore
    private let connectionStore: PlexConnectionStore
    private let libraryStore: PlexLibraryStore
    private let browserStore: PlexBrowserStore
    private let transferCoordinator: PlexDownloadTransferCoordinator
    private let playbackCapabilities: PlexPlaybackCapabilities

    init(
        authStore: PlexAuthStore,
        connectionStore: PlexConnectionStore,
        libraryStore: PlexLibraryStore,
        browserStore: PlexBrowserStore,
        transferCoordinator: PlexDownloadTransferCoordinator,
        playbackCapabilities: PlexPlaybackCapabilities = NativePlaybackCapabilityProbe.current()
    ) {
        self.authStore = authStore
        self.connectionStore = connectionStore
        self.libraryStore = libraryStore
        self.browserStore = browserStore
        self.transferCoordinator = transferCoordinator
        self.playbackCapabilities = playbackCapabilities
    }

    func start() async throws {
        try await transferCoordinator.start()
    }

    func decisionParameters(
        for item: PlexMediaItem,
        source: PlexPlaybackSource,
        sessionIdentifier: String,
        clientProfileName: String? = "generic",
        clientProfileExtra: String? = nil
    ) throws -> PlexDownloadDecisionParameters {
        let mediaKind = item.media.indices.contains(source.mediaIndex)
            ? PlexPlaybackMediaKind(media: item.media[source.mediaIndex])
            : nil
        let nativeDirectPlaySupported = playbackCapabilities.directPlayPath(
            for: item,
            source: source
        ) != nil
        return try connectionStore.settings.downloadPreferences.decisionParameters(
            for: item,
            source: source,
            sessionIdentifier: sessionIdentifier,
            nativeDirectPlaySupported: nativeDirectPlaySupported,
            clientProfileName: clientProfileName,
            clientProfileExtra: clientProfileExtra
                ?? mediaKind.map(playbackCapabilities.downloadClientProfileExtra(for:))
        )
    }

    func authorization(
        forLibraryID libraryID: String
    ) async throws -> PlexDownloadCreationAuthorization {
        guard connectionStore.settings.hasAuthenticatedAccount,
              let user = authStore.authenticatedUser else {
            throw PlexDownloadCreationAuthorizationError.signedOut
        }
        guard let library = libraryStore.libraries.first(where: { $0.id == libraryID }) else {
            throw PlexDownloadCreationAuthorizationError.unavailableLibrary
        }

        let configuration = try await connectionStore.currentConfiguration()
        guard let serverIdentifier = configuration.serverIdentifier?.nilIfBlank else {
            throw PlexDownloadCreationAuthorizationError.missingServerIdentity
        }
        let endpoints = try await browserStore.downloadProviderEndpoints(using: configuration)
        let facts = PlexDownloadAuthorization(
            user: user,
            library: library,
            providerEndpoints: endpoints
        )
        try Self.requireAuthorization(facts)

        let authorization = PlexDownloadCreationAuthorization(
            scope: PlexDownloadAuthorizationScope(
                accountID: user.id,
                serverIdentifier: serverIdentifier,
                serverURL: Self.normalizedServerURL(configuration.serverURL),
                libraryID: library.id,
                providerIdentifier: endpoints.providerIdentifier
            ),
            facts: facts
        )
        guard isCurrent(authorization) else {
            throw PlexDownloadCreationAuthorizationError.authorizationExpired
        }
        return authorization
    }

    func isCurrentlyAuthorized(forLibraryID libraryID: String) -> Bool {
        guard connectionStore.settings.hasAuthenticatedAccount,
              let user = authStore.authenticatedUser,
              let library = libraryStore.libraries.first(where: { $0.id == libraryID }),
              let facts = browserStore.downloadAuthorization(
                  for: user,
                  library: library
              ) else {
            return false
        }
        return facts.isAuthorized
    }

    func schedule(
        _ transferRequest: PlexDownloadTransferRequest,
        forLibraryID libraryID: String,
        transferID: UUID = UUID(),
        createdAt: Date = Date()
    ) async throws -> PlexDownloadTransferRecord {
        let authorization = try await authorization(forLibraryID: libraryID)
        return try await schedule(
            transferRequest,
            authorization: authorization,
            transferID: transferID,
            createdAt: createdAt
        )
    }

    func schedule(
        _ transferRequest: PlexDownloadTransferRequest,
        authorization: PlexDownloadCreationAuthorization,
        transferID: UUID = UUID(),
        createdAt: Date = Date()
    ) async throws -> PlexDownloadTransferRecord {
        guard isCurrent(authorization) else {
            throw PlexDownloadCreationAuthorizationError.authorizationExpired
        }
        guard Self.matches(transferRequest, authorization: authorization) else {
            throw PlexDownloadCreationAuthorizationError.mismatchedTransfer
        }

        let record: PlexDownloadTransferRecord
        do {
            record = try await transferCoordinator.schedule(
                transferRequest,
                transferID: transferID,
                createdAt: createdAt,
                authorizationCheck: { @MainActor [weak self] in
                    self?.isCurrent(authorization) == true
                }
            )
        } catch PlexDownloadTransferError.authorizationExpired {
            throw PlexDownloadCreationAuthorizationError.authorizationExpired
        }

        guard isCurrent(authorization) else {
            try? await transferCoordinator.cancel(transferID: record.id)
            throw PlexDownloadCreationAuthorizationError.authorizationExpired
        }
        return record
    }

    func isCurrent(_ authorization: PlexDownloadCreationAuthorization) -> Bool {
        guard connectionStore.settings.hasAuthenticatedAccount,
              let user = authStore.authenticatedUser,
              user.id == authorization.scope.accountID,
              connectionStore.settings.selectedServerIdentifier?.nilIfBlank
                == authorization.scope.serverIdentifier,
              let serverURL = connectionStore.resolvedServerURL,
              Self.normalizedServerURL(serverURL) == authorization.scope.serverURL,
              let library = libraryStore.libraries.first(where: {
                  $0.id == authorization.scope.libraryID
              }),
              let facts = browserStore.downloadAuthorization(
                  for: user,
                  library: library
              ),
              facts == authorization.facts,
              facts.isAuthorized,
              browserStore.presentedProviderEndpoints?.providerIdentifier
                == authorization.scope.providerIdentifier else {
            return false
        }
        return true
    }

    private static func requireAuthorization(
        _ authorization: PlexDownloadAuthorization
    ) throws {
        guard authorization.accountHasDownloadsEntitlement else {
            throw PlexDownloadCreationAuthorizationError.accountNotEntitled
        }
        guard authorization.serverAllowsSync == true else {
            throw PlexDownloadCreationAuthorizationError.serverDisallowsDownloads
        }
        guard authorization.libraryAllowsSync == true else {
            throw PlexDownloadCreationAuthorizationError.libraryDisallowsDownloads
        }
        guard authorization.libraryProviderSupportsDownloads else {
            throw PlexDownloadCreationAuthorizationError.providerDisallowsDownloads
        }
    }

    private static func matches(
        _ transferRequest: PlexDownloadTransferRequest,
        authorization: PlexDownloadCreationAuthorization
    ) -> Bool {
        let identity = transferRequest.packageIdentity
        guard identity.accountID == authorization.scope.accountID,
              identity.serverIdentifier == authorization.scope.serverIdentifier,
              transferRequest.request.url.map({
                  sameOrigin($0, authorization.scope.serverURL)
              }) == true,
              transferRequest.request.url?.path
                == "/downloadQueue/\(identity.queueID)/item/\(identity.queueItemID)/media",
              let decision = try? JSONDecoder()
                .decode(PlexDownloadQueueDecisionEnvelope.self, from: transferRequest.decisionData)
                .mediaContainer,
              decision.allowSync == true,
              let metadata = decision.metadata.first(where: {
                  $0.ratingKey == identity.ratingKey
              }),
              metadata.librarySectionID == authorization.scope.libraryID,
              metadata.key?.nilIfBlank == identity.metadataKey.nilIfBlank else {
            return false
        }
        return true
    }

    private static func normalizedServerURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        while components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        return components.url ?? url
    }

    private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let left = URLComponents(url: lhs, resolvingAgainstBaseURL: false),
              let right = URLComponents(url: rhs, resolvingAgainstBaseURL: false) else {
            return false
        }
        return left.scheme?.lowercased() == right.scheme?.lowercased()
            && left.host?.lowercased() == right.host?.lowercased()
            && effectivePort(left) == effectivePort(right)
            && left.user == nil
            && left.password == nil
    }

    private static func effectivePort(_ components: URLComponents) -> Int? {
        if let port = components.port {
            return port
        }
        return switch components.scheme?.lowercased() {
        case "http": 80
        case "https": 443
        default: nil
        }
    }
}
