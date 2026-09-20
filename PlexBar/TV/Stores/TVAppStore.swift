import PlexTopShelf
import PlexClientKit
import PlexModels
import Foundation
import Observation

@MainActor
@Observable
final class TVAppStore {
    enum Tab: Hashable {
        case home
        case libraries
        case search
        case settings
    }

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected(serverName: String)
    }

    private enum DefaultsKey {
        static let selectedServerIdentifier = "tv.plex.selectedServerIdentifier"
        static let skipIntroBehavior = "tv.playback.skipIntroBehavior"
        static let skipAdsBehavior = "tv.playback.skipAdsBehavior"
        static let skipCreditsBehavior = "tv.playback.skipCreditsBehavior"
        static let autoplayNextEpisode = "tv.playback.autoplayNextEpisode"
        static let legacyVideoQuality = "tv.playback.videoQuality"
        static let localVideoQuality = "tv.playback.localVideoQuality"
        static let remoteVideoQuality = "tv.playback.remoteVideoQuality"
        static let remoteMusicQuality = "tv.playback.remoteMusicQuality"
        static let audioBoost = "tv.playback.audioBoost"
        static let videoScalingMode = "tv.playback.videoScalingMode"
        static let cinemaPreplayPreference = "tv.playback.cinemaPreplayPreference"
        static let rewindOnResumeSeconds = "tv.playback.rewindOnResumeSeconds"
        static let autoplayCountdown = "tv.playback.autoplayCountdown"
        static let passoutProtection = "tv.playback.passoutProtection"
        static let qualitySuggestionsEnabled = "tv.playback.qualitySuggestionsEnabled"
        static let automaticallyAdjustVideoQuality = "tv.playback.automaticallyAdjustVideoQuality"
        static let playSmallerVideosAtOriginalQuality = "tv.playback.playSmallerVideosAtOriginalQuality"
        static let allowsDirectPlay = "tv.playback.allowsDirectPlay"
        static let allowsDirectStream = "tv.playback.allowsDirectStream"
        static let forceDirectPlay = "tv.playback.forceDirectPlay"
        static let subtitleBurnMode = "tv.playback.subtitleBurnMode"
        static let subtitleSize = "tv.playback.subtitleSize"
        static let automaticallySyncSubtitles = "tv.playback.automaticallySyncSubtitles"
    }

    private let client: TVPlexClient
    private let authClient: PlexAuthClient
    private let deviceIdentityStore: any PlexDeviceIdentityProviding
    private let keychain: KeychainStore
    private let defaults: UserDefaults
    private let accountStorage: TVPlexAccountJWTStorage
    private let accountJWTManager: PlexAccountJWTManager
    private var libraryRequestIDs: [String: UUID] = [:]
    private var libraryQueries: [String: LibraryQuery] = [:]
    private var libraryNextOffsets: [String: Int] = [:]
    private var libraryPaginationFailureIDs: Set<String> = []

    private struct LibraryQuery: Equatable {
        let connection: TVPlexConnection
        let options: PlexLibraryBrowseOptions
    }
    private var searchTask: Task<Void, Never>?
    private var signInTask: Task<Void, Never>?
    private var accountTokenRefreshTask: Task<Void, Never>?
    private var playbackPreparationTask: Task<Void, Never>?
    private var playbackPreparationID = UUID()
    private var homeRefreshID = UUID()
    private let topShelfPublisher: TVTopShelfPublisher
    private var topShelfRouteTask: Task<Void, Never>?
    private var pendingTopShelfRoute: TVTopShelfRoute?
    private var hasRestoredSession = false
    private var sessionRevision = UUID()

    var selectedTab: Tab = .home
    var homePath: [TVNavigationRoute] = []
    var connectionState: ConnectionState = .disconnected
    var homeHubs: [PlexHub] = []
    var libraries: [TVPlexLibrary] = []
    var libraryItems: [String: [PlexMediaItem]] = [:]
    var libraryTotalSizes: [String: Int] = [:]
    var libraryErrors: [String: String] = [:]
    var searchQuery = ""
    var searchHubs: [PlexHub] = []
    var searchErrorMessage: String?
    var isLoadingHome = false
    var isLoadingLibraries = false
    var isSearching = false
    var errorMessage: String?
    var playbackRequest: TVPlexPlaybackRequest?
    private(set) var playbackMetadataRevision = UUID()
    private(set) var playbackSleepTimer = PlexPlaybackSleepTimer.off
    private(set) var playbackPreparation: TVPlaybackPreparation?
    var signInCode: String?
    var availableServers: [PlexServerResource] = []
    var isPairing = true
    var skipIntroBehavior: PlexPlaybackMarkerBehavior {
        didSet {
            defaults.set(skipIntroBehavior.rawValue, forKey: DefaultsKey.skipIntroBehavior)
        }
    }
    var skipAdsBehavior: PlexPlaybackMarkerBehavior {
        didSet {
            defaults.set(skipAdsBehavior.rawValue, forKey: DefaultsKey.skipAdsBehavior)
        }
    }
    var skipCreditsBehavior: PlexPlaybackMarkerBehavior {
        didSet {
            defaults.set(skipCreditsBehavior.rawValue, forKey: DefaultsKey.skipCreditsBehavior)
        }
    }
    var autoplayNextEpisode: Bool {
        didSet {
            defaults.set(autoplayNextEpisode, forKey: DefaultsKey.autoplayNextEpisode)
        }
    }
    var localVideoQuality: PlexVideoQuality {
        didSet {
            defaults.set(localVideoQuality.rawValue, forKey: DefaultsKey.localVideoQuality)
        }
    }
    var remoteVideoQuality: PlexVideoQuality {
        didSet {
            defaults.set(remoteVideoQuality.rawValue, forKey: DefaultsKey.remoteVideoQuality)
        }
    }
    var remoteMusicQuality: PlexMusicQuality {
        didSet {
            defaults.set(remoteMusicQuality.rawValue, forKey: DefaultsKey.remoteMusicQuality)
        }
    }
    var audioBoost: PlexAudioBoost {
        didSet {
            defaults.set(audioBoost.rawValue, forKey: DefaultsKey.audioBoost)
        }
    }
    var videoScalingMode: PlexVideoScalingMode {
        didSet {
            defaults.set(videoScalingMode.rawValue, forKey: DefaultsKey.videoScalingMode)
        }
    }
    var cinemaPreplayPreference: PlexCinemaPreplayPreference {
        didSet {
            defaults.set(
                cinemaPreplayPreference.rawValue,
                forKey: DefaultsKey.cinemaPreplayPreference
            )
        }
    }
    var rewindOnResume: PlexRewindOnResume {
        didSet {
            defaults.set(
                rewindOnResume.seconds,
                forKey: DefaultsKey.rewindOnResumeSeconds
            )
        }
    }
    var autoplayCountdown: PlexAutoplayCountdown {
        didSet {
            defaults.set(String(autoplayCountdown.rawValue), forKey: DefaultsKey.autoplayCountdown)
        }
    }
    var passoutProtection: PlexPassoutProtection {
        didSet {
            defaults.set(
                passoutProtection.rawValue,
                forKey: DefaultsKey.passoutProtection
            )
        }
    }
    var qualitySuggestionsEnabled: Bool {
        didSet {
            defaults.set(
                qualitySuggestionsEnabled,
                forKey: DefaultsKey.qualitySuggestionsEnabled
            )
        }
    }
    var automaticallyAdjustVideoQuality: Bool {
        didSet {
            defaults.set(
                automaticallyAdjustVideoQuality,
                forKey: DefaultsKey.automaticallyAdjustVideoQuality
            )
        }
    }
    var playSmallerVideosAtOriginalQuality: Bool {
        didSet {
            defaults.set(
                playSmallerVideosAtOriginalQuality,
                forKey: DefaultsKey.playSmallerVideosAtOriginalQuality
            )
        }
    }
    var allowsDirectPlay: Bool {
        didSet {
            defaults.set(allowsDirectPlay, forKey: DefaultsKey.allowsDirectPlay)
        }
    }
    var allowsDirectStream: Bool {
        didSet {
            defaults.set(allowsDirectStream, forKey: DefaultsKey.allowsDirectStream)
        }
    }
    var forceDirectPlay: Bool {
        didSet {
            defaults.set(forceDirectPlay, forKey: DefaultsKey.forceDirectPlay)
        }
    }
    var subtitleBurnMode: PlexSubtitleBurnMode {
        didSet {
            defaults.set(subtitleBurnMode.rawValue, forKey: DefaultsKey.subtitleBurnMode)
        }
    }
    var subtitleSize: PlexSubtitleSize {
        didSet {
            defaults.set(subtitleSize.rawValue, forKey: DefaultsKey.subtitleSize)
        }
    }
    var automaticallySyncSubtitles: Bool {
        didSet {
            defaults.set(
                automaticallySyncSubtitles,
                forKey: DefaultsKey.automaticallySyncSubtitles
            )
        }
    }

    private(set) var connection: TVPlexConnection? {
        didSet {
            guard oldValue != connection else { return }
            topShelfRouteTask?.cancel()
            cancelPlaybackPreparation()
            homePath = []
            if oldValue?.serverIdentifier != connection?.serverIdentifier {
                homeRefreshID = UUID()
                isLoadingHome = false
                isLoadingLibraries = false
                homeHubs = []
                resetLibraries()
                topShelfPublisher.clear()
            }
        }
    }

    var isConnected: Bool {
        connection != nil
    }

    var hasAuthorizedAccount: Bool {
        accountStorage.storedAccountToken.nilIfBlank != nil
    }

    var serverName: String {
        guard case .connected(let serverName) = connectionState else { return "Plex" }
        return serverName
    }

    var playbackMarkerPreferences: PlexPlaybackMarkerPreferences {
        PlexPlaybackMarkerPreferences(
            intro: skipIntroBehavior,
            ads: skipAdsBehavior,
            credits: skipCreditsBehavior
        )
    }

    var autoplayPreferences: PlexAutoplayPreferences {
        PlexAutoplayPreferences(
            isEnabled: autoplayNextEpisode,
            countdown: autoplayCountdown,
            passoutProtection: passoutProtection
        )
    }

    var activeVideoQuality: PlexVideoQuality {
        videoQualityPreferences.quality(for: connection?.kind)
    }

    var activeMusicQuality: PlexMusicQuality {
        musicQualityPreferences.quality(for: connection?.kind)
    }

    var playbackStreamingPolicy: PlexPlaybackStreamingPolicy {
        PlexPlaybackStreamingPolicy(
            allowsDirectPlay: allowsDirectPlay,
            allowsDirectStream: allowsDirectStream,
            forceDirectPlay: forceDirectPlay
        )
    }

    private var videoQualityPreferences: PlexVideoQualityPreferences {
        PlexVideoQualityPreferences(
            local: localVideoQuality,
            remote: remoteVideoQuality
        )
    }

    private var musicQualityPreferences: PlexMusicQualityPreferences {
        PlexMusicQualityPreferences(remote: remoteMusicQuality)
    }

    init(
        client: TVPlexClient = TVPlexClient(),
        defaults: UserDefaults = .standard,
        authClient: PlexAuthClient = PlexAuthClient(),
        deviceIdentityStore: any PlexDeviceIdentityProviding = PlexKeychainDeviceIdentityStore(keychain: KeychainStore(service: TVAppConfiguration.bundleIdentifier)),
        keychain: KeychainStore = KeychainStore(service: TVAppConfiguration.bundleIdentifier),
        topShelfPublisher: TVTopShelfPublisher = TVTopShelfPublisher(),
        accountStorage: TVPlexAccountJWTStorage? = nil
    ) {
        self.client = client
        self.authClient = authClient
        self.deviceIdentityStore = deviceIdentityStore
        self.keychain = keychain
        self.defaults = defaults
        self.topShelfPublisher = topShelfPublisher
        let accountStorage = accountStorage ?? TVPlexAccountJWTStorage(defaults: defaults, keychain: keychain)
        self.accountStorage = accountStorage
        accountJWTManager = PlexAccountJWTManager(
            storage: accountStorage,
            clientContext: { PlexClientContext(clientIdentifier: $0) },
            client: authClient,
            deviceIdentityStore: deviceIdentityStore
        )
        skipIntroBehavior = defaults.string(forKey: DefaultsKey.skipIntroBehavior)
            .flatMap(PlexPlaybackMarkerBehavior.init(rawValue:)) ?? .manually
        skipAdsBehavior = defaults.string(forKey: DefaultsKey.skipAdsBehavior)
            .flatMap(PlexPlaybackMarkerBehavior.init(rawValue:)) ?? .manually
        skipCreditsBehavior = defaults.string(forKey: DefaultsKey.skipCreditsBehavior)
            .flatMap(PlexPlaybackMarkerBehavior.init(rawValue:)) ?? .manually
        autoplayNextEpisode = defaults.object(forKey: DefaultsKey.autoplayNextEpisode) as? Bool ?? true
        let legacyVideoQuality = defaults.string(forKey: DefaultsKey.legacyVideoQuality)
            .flatMap(PlexVideoQuality.init(rawValue:))
        localVideoQuality = defaults.string(forKey: DefaultsKey.localVideoQuality)
            .flatMap(PlexVideoQuality.init(rawValue:))
            ?? legacyVideoQuality
            ?? .original
        remoteVideoQuality = defaults.string(forKey: DefaultsKey.remoteVideoQuality)
            .flatMap(PlexVideoQuality.init(rawValue:))
            ?? legacyVideoQuality
            ?? .original
        remoteMusicQuality = defaults.string(forKey: DefaultsKey.remoteMusicQuality)
            .flatMap(PlexMusicQuality.init(rawValue:))
            ?? .original
        audioBoost = (defaults.object(forKey: DefaultsKey.audioBoost) as? Int)
            .flatMap(PlexAudioBoost.init(rawValue:))
            ?? .none
        videoScalingMode = defaults.string(forKey: DefaultsKey.videoScalingMode)
            .flatMap(PlexVideoScalingMode.init(rawValue:))
            ?? .fit
        cinemaPreplayPreference = (
            defaults.object(forKey: DefaultsKey.cinemaPreplayPreference) as? Int
        )
            .flatMap(PlexCinemaPreplayPreference.init(rawValue:))
            ?? .off
        rewindOnResume = PlexRewindOnResume(
            seconds: defaults.object(forKey: DefaultsKey.rewindOnResumeSeconds) as? Int ?? 0
        )
        autoplayCountdown = defaults.string(forKey: DefaultsKey.autoplayCountdown)
            .flatMap(Int.init)
            .flatMap(PlexAutoplayCountdown.init(rawValue:))
            ?? .fifteenSeconds
        passoutProtection = (defaults.object(forKey: DefaultsKey.passoutProtection) as? Int)
            .flatMap(PlexPassoutProtection.init(rawValue:))
            ?? .twoHours
        qualitySuggestionsEnabled = defaults.object(
            forKey: DefaultsKey.qualitySuggestionsEnabled
        ) as? Bool ?? true
        automaticallyAdjustVideoQuality = defaults.object(
            forKey: DefaultsKey.automaticallyAdjustVideoQuality
        ) as? Bool ?? false
        playSmallerVideosAtOriginalQuality = defaults.object(
            forKey: DefaultsKey.playSmallerVideosAtOriginalQuality
        ) as? Bool ?? true
        allowsDirectPlay = defaults.object(
            forKey: DefaultsKey.allowsDirectPlay
        ) as? Bool ?? true
        allowsDirectStream = defaults.object(
            forKey: DefaultsKey.allowsDirectStream
        ) as? Bool ?? true
        forceDirectPlay = defaults.object(
            forKey: DefaultsKey.forceDirectPlay
        ) as? Bool ?? false
        subtitleBurnMode = defaults.string(forKey: DefaultsKey.subtitleBurnMode)
            .flatMap(PlexSubtitleBurnMode.init(rawValue:))
            ?? .automatic
        subtitleSize = (defaults.object(forKey: DefaultsKey.subtitleSize) as? Int)
            .flatMap(PlexSubtitleSize.init(rawValue:))
            ?? .normal
        automaticallySyncSubtitles = defaults.object(
            forKey: DefaultsKey.automaticallySyncSubtitles
        ) as? Bool ?? true
    }

    func restoreSession() async {
        guard !hasRestoredSession else { return }
        let revision = sessionRevision
        defer {
            hasRestoredSession = true
            if revision == sessionRevision { processPendingTopShelfRoute() }
        }
        guard !isConnected else { return }
        isPairing = false
        do {
            try await accountStorage.loadAccountToken()
            try requireCurrentSession(revision)
        } catch {
            guard revision == sessionRevision, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            return
        }
        guard hasAuthorizedAccount else {
            topShelfPublisher.clear()
            return
        }
        await reconnectAuthorizedAccount()
    }

    @discardableResult
    private func connect(to server: PlexServerResource) async -> Bool {
        let revision = sessionRevision
        connectionState = .connecting
        errorMessage = nil

        do {
            let resolved = try await client.resolve(
                server,
                clientIdentifier: accountStorage.clientIdentifier
            )
            guard revision == sessionRevision else { return false }
            connection = resolved.connection
            connectionState = .connected(
                serverName: resolved.identity.friendlyName ?? server.name
            )
            await refreshAll()
            guard revision == sessionRevision, connection == resolved.connection else { return false }
            processPendingTopShelfRoute()
            return true
        } catch {
            guard revision == sessionRevision else { return false }
            connection = nil
            connectionState = .disconnected
            errorMessage = error.localizedDescription
            return false
        }
    }

    func startPlexDeviceAuthorization() {
        sessionRevision = UUID()
        let revision = sessionRevision
        accountJWTManager.invalidatePreparation()
        accountTokenRefreshTask?.cancel()
        signInTask?.cancel()
        isPairing = true
        signInCode = nil
        availableServers = []
        errorMessage = nil
        let clientContext = PlexClientContext(clientIdentifier: accountStorage.clientIdentifier)

        signInTask = Task { [weak self] in
            guard let self else { return }
            do {
                let identity = try await deviceIdentityStore.loadOrCreateIdentity()
                try requireCurrentSession(revision)
                let pin = try await authClient.createPin(
                    jwk: identity.publicJWK(includeUse: false),
                    strong: false,
                    clientContext: clientContext
                )
                try requireCurrentSession(revision)
                let deviceJWT = try identity.signedDeviceJWT(
                    clientIdentifier: accountStorage.clientIdentifier
                )
                signInCode = pin.code.uppercased()

                for _ in 0..<150 {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .seconds(2))
                    let currentPin = try await authClient.fetchPin(
                        id: String(pin.id),
                        deviceJWT: deviceJWT,
                        clientContext: clientContext
                    )
                    try requireCurrentSession(revision)
                    guard let userToken = currentPin.authToken?.nilIfBlank else { continue }
                    let preparedToken = try await accountJWTManager.acceptNewAccountToken(
                        userToken,
                        registeredKeyID: identity.keyID
                    )
                    try requireCurrentSession(revision)
                    scheduleAccountTokenRefresh(preparedToken)
                    let servers = try await fetchAuthorizedServers()
                    try requireCurrentSession(revision)
                    isPairing = false
                    signInCode = nil
                    await presentDiscoveredServers(servers, preferStoredSelection: true, revision: revision)
                    return
                }

                isPairing = false
                signInCode = nil
                errorMessage = "The Plex link code expired. Start sign-in again for a new code."
            } catch is CancellationError {
                return
            } catch {
                guard revision == sessionRevision, !Task.isCancelled else { return }
                isPairing = false
                signInCode = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func selectServer(_ server: PlexServerResource) async {
        let revision = sessionRevision
        guard hasAuthorizedAccount, availableServers.contains(server) else { return }
        guard !server.connections.isEmpty else {
            errorMessage = "\(server.name) has no available connections."
            return
        }
        availableServers = []
        if await connect(to: server), revision == sessionRevision, hasAuthorizedAccount, !Task.isCancelled {
            defaults.set(server.id, forKey: DefaultsKey.selectedServerIdentifier)
        }
    }

    func reconnectAuthorizedAccount() async {
        let revision = sessionRevision
        guard hasAuthorizedAccount else {
            startPlexDeviceAuthorization()
            return
        }

        connectionState = .connecting
        availableServers = []
        errorMessage = nil
        do {
            let servers = try await fetchAuthorizedServers()
            try requireCurrentSession(revision)
            await presentDiscoveredServers(servers, preferStoredSelection: true, revision: revision)
        } catch {
            guard revision == sessionRevision, !Task.isCancelled else { return }
            connection = nil
            connectionState = .disconnected
            errorMessage = error.localizedDescription
        }
    }

    func chooseServer() async {
        let revision = sessionRevision
        guard hasAuthorizedAccount else {
            startPlexDeviceAuthorization()
            return
        }

        do {
            let servers = try await fetchAuthorizedServers()
            try requireCurrentSession(revision)
            availableServers = servers
            playbackRequest = nil
            connection = nil
            connectionState = .disconnected
        } catch {
            guard revision == sessionRevision, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func refreshAll() async {
        guard let connection else { return }
        let refreshID = UUID()
        homeRefreshID = refreshID
        isLoadingHome = true
        isLoadingLibraries = true
        errorMessage = nil

        async let homeResult: Result<[PlexHub], Error> = {
            do { return .success(try await client.fetchHome(connection: connection)) }
            catch { return .failure(error) }
        }()
        async let librariesResult: Result<[TVPlexLibrary], Error> = {
            do { return .success(try await client.fetchLibraries(connection: connection)) }
            catch { return .failure(error) }
        }()
        let (home, libraryList) = await (homeResult, librariesResult)
        guard homeRefreshID == refreshID, self.connection == connection else { return }

        switch home {
        case .success(let hubs):
            homeHubs = hubs
            topShelfPublisher.publish(hubs: homeHubs, connection: connection, client: client)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
        switch libraryList {
        case .success(let values):
            libraries = values
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
        isLoadingHome = false
        isLoadingLibraries = false
    }

    func libraryBrowseDefinition(_ library: TVPlexLibrary) async throws -> PlexLibraryBrowseDefinition {
        guard let connection else { throw TVPlexError.notConnected }
        let definition = try await client.fetchLibraryBrowseDefinition(library, connection: connection)
        guard self.connection == connection else { throw CancellationError() }
        return definition
    }

    func libraryFilterValues(_ filter: PlexLibraryFilterDefinition) async throws -> [PlexLibraryFilterValue] {
        guard let connection else { throw TVPlexError.notConnected }
        let values = try await client.fetchLibraryFilterValues(filter, connection: connection)
        guard self.connection == connection else { throw CancellationError() }
        return values
    }

    func loadLibrary(_ library: TVPlexLibrary, options: PlexLibraryBrowseOptions = .default, refresh: Bool = false) async {
        guard let connection else { return }
        let query = LibraryQuery(connection: connection, options: options)
        let queryChanged = libraryQueries[library.id] != query
        if !queryChanged, !refresh, libraryItems[library.id] != nil { return }
        let requestID = UUID()
        libraryRequestIDs[library.id] = requestID
        libraryQueries[library.id] = query
        libraryErrors[library.id] = nil
        libraryPaginationFailureIDs.remove(library.id)
        if queryChanged {
            libraryItems[library.id] = nil
            libraryTotalSizes[library.id] = nil
            libraryNextOffsets[library.id] = nil
        }
        defer {
            if libraryRequestIDs[library.id] == requestID { libraryRequestIDs[library.id] = nil }
        }
        do {
            let page = try await client.fetchLibrary(library, options: options, connection: connection)
            try Task.checkCancellation()
            guard libraryRequestIDs[library.id] == requestID, self.connection == connection else { return }
            libraryItems[library.id] = page.items
            libraryNextOffsets[library.id] = page.offset + page.items.count
            libraryTotalSizes[library.id] = page.totalSize ?? page.items.count
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            guard libraryRequestIDs[library.id] == requestID, self.connection == connection else { return }
            libraryErrors[library.id] = error.localizedDescription
        }
    }

    func loadMoreLibraryItems(_ library: TVPlexLibrary, currentItem: PlexMediaItem) async {
        guard let connection,
              !isLoading(library),
              let query = libraryQueries[library.id], query.connection == connection,
              let items = libraryItems[library.id], items.last?.id == currentItem.id,
              let offset = libraryNextOffsets[library.id],
              offset < (libraryTotalSizes[library.id] ?? offset) else { return }
        let requestID = UUID()
        libraryRequestIDs[library.id] = requestID
        libraryErrors[library.id] = nil
        defer {
            if libraryRequestIDs[library.id] == requestID { libraryRequestIDs[library.id] = nil }
        }
        do {
            let page = try await client.fetchLibrary(library, start: offset, options: query.options, connection: connection)
            try Task.checkCancellation()
            guard libraryRequestIDs[library.id] == requestID, self.connection == connection else { return }
            guard page.offset == offset, !page.items.isEmpty else { throw PlexAPIError.invalidResponse }
            let existingIDs = Set(items.map(\.id))
            libraryItems[library.id] = items + page.items.filter { !existingIDs.contains($0.id) }
            libraryNextOffsets[library.id] = page.offset + page.items.count
            libraryTotalSizes[library.id] = page.totalSize ?? libraryTotalSizes[library.id]
            libraryPaginationFailureIDs.remove(library.id)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            guard libraryRequestIDs[library.id] == requestID, self.connection == connection else { return }
            libraryPaginationFailureIDs.insert(library.id)
            libraryErrors[library.id] = error.localizedDescription
        }
    }

    func retryLibrary(_ library: TVPlexLibrary, options: PlexLibraryBrowseOptions) async {
        if libraryPaginationFailureIDs.contains(library.id), let last = libraryItems[library.id]?.last {
            await loadMoreLibraryItems(library, currentItem: last)
        } else {
            await loadLibrary(library, options: options, refresh: true)
        }
    }

    func isLoading(_ library: TVPlexLibrary) -> Bool {
        libraryRequestIDs[library.id] != nil
    }

    func submitSearch() {
        searchTask?.cancel()
        searchErrorMessage = nil
        searchHubs = []
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let connection else {
            searchHubs = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))
                let hubs = try await client.search(query: query, connection: connection)
                guard !Task.isCancelled, self.connection == connection,
                      query == searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    return
                }
                searchHubs = hubs
                isSearching = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.connection == connection,
                      query == searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                searchErrorMessage = error.localizedDescription
                isSearching = false
            }
        }
    }

    func resolvedItem(_ item: PlexMediaItem) async throws -> PlexMediaItem {
        guard let connection else { throw TVPlexError.notConnected }
        return try await client.fetchMetadata(ratingKey: item.ratingKey, connection: connection)
    }

    func hubPage(path: String, start: Int) async throws -> PlexMediaPage {
        guard let connection else { throw TVPlexError.notConnected }
        let page = try await client.fetchHubPage(path: path, start: start, connection: connection)
        try Task.checkCancellation()
        guard self.connection == connection else { throw CancellationError() }
        return page
    }

    func mediaExtras(for item: PlexMediaItem) async throws -> [PlexMediaItem] {
        guard item.supportsMediaExtras else { return [] }
        guard let connection else { throw TVPlexError.notConnected }
        let extras = try await client.fetchMediaExtras(ratingKey: item.ratingKey, connection: connection)
        guard self.connection == connection else { throw CancellationError() }
        return extras
    }

    func relatedHubs(for item: PlexMediaItem) async throws -> [PlexHub] {
        guard let connection else { throw TVPlexError.notConnected }
        let hubs = try await client.fetchRelatedHubs(ratingKey: item.ratingKey, connection: connection)
        guard self.connection == connection else { throw CancellationError() }
        return hubs
    }

    func episodeSeriesCast(for item: PlexMediaItem) async throws -> [PlexTag] {
        guard let connection else { throw TVPlexError.notConnected }
        return try await client.fetchEpisodeSeriesCast(for: item, connection: connection)
    }

    func children(of item: PlexMediaItem) async throws -> [PlexMediaItem] {
        guard let connection else { throw TVPlexError.notConnected }
        return try await client.fetchChildren(of: item, connection: connection)
    }

    func seasonEpisodes(ratingKey: String) async -> [PlexMediaItem] {
        guard let connection else { return [] }
        do {
            let episodes = try await client.fetchChildren(ratingKey: ratingKey, connection: connection)
            try Task.checkCancellation()
            return episodes.filter { $0.type?.lowercased() == "episode" }
        } catch is CancellationError {
            return []
        } catch {
            guard !Task.isCancelled else { return [] }
            errorMessage = error.localizedDescription
            return []
        }
    }

    func seriesSeasons(ratingKey: String) async -> [PlexMediaItem] {
        guard let connection else { return [] }
        do {
            let seasons = try await client.fetchChildren(ratingKey: ratingKey, connection: connection)
            try Task.checkCancellation()
            return seasons.filter { $0.type?.lowercased() == "season" }
        } catch is CancellationError {
            return []
        } catch {
            guard !Task.isCancelled else { return [] }
            errorMessage = error.localizedDescription
            return []
        }
    }

    func personDetails(for route: PlexPersonRoute) async throws -> TVPlexPersonDetails {
        guard let connection else {
            throw TVPlexError.notConnected
        }

        async let person = client.fetchPerson(
            identifier: route.identifier,
            connection: connection
        )
        async let media = client.fetchPersonMedia(
            identifier: route.identifier,
            connection: connection
        )
        return try await TVPlexPersonDetails(person: person, media: media)
    }

    func play(
        _ item: PlexMediaItem,
        source: PlexPlaybackSource? = nil,
        resume: Bool = true
    ) {
        play(
            item,
            source: source,
            resume: resume,
            playbackRate: .normal
        )
    }

    func play(
        _ item: PlexMediaItem,
        source: PlexPlaybackSource? = nil,
        resume: Bool,
        playbackRate: PlexPlaybackRate
    ) {
        preparePlayback(for: item, kind: .content) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await initialPlaybackRequest(
                for: item,
                source: source,
                resume: resume,
                playbackRate: playbackRate
            )
        }
    }

    func playPrimaryExtra(for item: PlexMediaItem) {
        guard let path = item.primaryExtraKey?.nilIfBlank else {
            errorMessage = PlexAPIError.invalidResponse.localizedDescription
            return
        }
        preparePlayback(for: item, kind: .primaryExtra) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await primaryExtraPlaybackRequest(path: path)
        }
    }

    func isPreparingPlayback(
        _ item: PlexMediaItem,
        kind: TVPlaybackPreparationKind = .content
    ) -> Bool {
        playbackPreparation == TVPlaybackPreparation(
            itemRatingKey: item.ratingKey,
            kind: kind
        )
    }

    private func preparePlayback(
        for item: PlexMediaItem,
        kind: TVPlaybackPreparationKind,
        request: @escaping @MainActor () async throws -> TVPlexPlaybackRequest
    ) {
        playbackPreparationTask?.cancel()
        let preparationID = UUID()
        playbackPreparationID = preparationID
        playbackPreparation = TVPlaybackPreparation(
            itemRatingKey: item.ratingKey,
            kind: kind
        )
        errorMessage = nil
        playbackPreparationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if playbackPreparationID == preparationID {
                    playbackPreparation = nil
                    playbackPreparationTask = nil
                }
            }
            do {
                let playbackRequest = try await request()
                try Task.checkCancellation()
                guard playbackPreparationID == preparationID else { return }
                self.playbackRequest = playbackRequest
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    func playResolved(
        _ item: PlexMediaItem,
        queue: PlexPlaybackQueue? = nil,
        resume: Bool,
        playbackRate: PlexPlaybackRate
    ) {
        cancelPlaybackPreparation()
        guard item.isPlayable else {
            errorMessage = "Choose a movie, episode, track, or trailer to play."
            return
        }
        playbackRequest = TVPlexPlaybackRequest(
            item: item,
            queue: queue,
            startTime: resume ? item.resumeSeconds : 0,
            playbackRate: playbackRate
        )
    }

    func presentPlayback(_ request: TVPlexPlaybackRequest) {
        cancelPlaybackPreparation()
        playbackRequest = request
    }

    func changeVideoQuality(
        to quality: PlexVideoQuality,
        for item: PlexMediaItem,
        queue: PlexPlaybackQueue?,
        source: PlexPlaybackSource?,
        queueSourcePreference: PlexPlaybackQueueSourcePreference?,
        at position: TimeInterval,
        autoplay: Bool,
        playbackRate: PlexPlaybackRate,
        forceVideoTranscode: Bool
    ) {
        playbackRequest = TVPlexPlaybackRequest(
            item: item,
            queue: queue,
            source: source,
            queueSourcePreference: queueSourcePreference,
            startTime: PlexPlaybackSeek.clamped(position, duration: item.durationSeconds),
            autoplay: autoplay,
            playbackRate: playbackRate,
            videoQualityOverride: quality,
            forceVideoTranscode: forceVideoTranscode
        )
    }

    func changeVideoConversionMode(
        forceVideoTranscode: Bool,
        videoQualityOverride: PlexVideoQuality?,
        for item: PlexMediaItem,
        queue: PlexPlaybackQueue?,
        source: PlexPlaybackSource?,
        queueSourcePreference: PlexPlaybackQueueSourcePreference?,
        at position: TimeInterval,
        autoplay: Bool,
        playbackRate: PlexPlaybackRate
    ) {
        playbackRequest = TVPlexPlaybackRequest(
            item: item,
            queue: queue,
            source: source,
            queueSourcePreference: queueSourcePreference,
            startTime: PlexPlaybackSeek.clamped(position, duration: item.durationSeconds),
            autoplay: autoplay,
            playbackRate: playbackRate,
            videoQualityOverride: videoQualityOverride,
            forceVideoTranscode: forceVideoTranscode
        )
    }

    func changeMusicQuality(
        to quality: PlexMusicQuality,
        for item: PlexMediaItem,
        queue: PlexPlaybackQueue?,
        source: PlexPlaybackSource?,
        queueSourcePreference: PlexPlaybackQueueSourcePreference?,
        at position: TimeInterval,
        autoplay: Bool,
        playbackRate: PlexPlaybackRate,
        videoQualityOverride: PlexVideoQuality?,
        forceVideoTranscode: Bool
    ) {
        guard connection?.kind != .local else { return }
        remoteMusicQuality = quality
        playbackRequest = TVPlexPlaybackRequest(
            item: item,
            queue: queue,
            source: source,
            queueSourcePreference: queueSourcePreference,
            startTime: PlexPlaybackSeek.clamped(position, duration: item.durationSeconds),
            autoplay: autoplay,
            playbackRate: playbackRate,
            videoQualityOverride: videoQualityOverride,
            forceVideoTranscode: forceVideoTranscode
        )
    }

    func changeAudioBoost(
        to audioBoost: PlexAudioBoost,
        for item: PlexMediaItem,
        queue: PlexPlaybackQueue?,
        source: PlexPlaybackSource?,
        queueSourcePreference: PlexPlaybackQueueSourcePreference?,
        at position: TimeInterval,
        autoplay: Bool,
        playbackRate: PlexPlaybackRate,
        videoQualityOverride: PlexVideoQuality?,
        forceVideoTranscode: Bool
    ) {
        self.audioBoost = audioBoost
        playbackRequest = TVPlexPlaybackRequest(
            item: item,
            queue: queue,
            source: source,
            queueSourcePreference: queueSourcePreference,
            startTime: PlexPlaybackSeek.clamped(position, duration: item.durationSeconds),
            autoplay: autoplay,
            playbackRate: playbackRate,
            videoQualityOverride: videoQualityOverride,
            forceVideoTranscode: forceVideoTranscode
        )
    }

    func changeSubtitleAutoSync(
        isEnabled: Bool,
        for item: PlexMediaItem,
        queue: PlexPlaybackQueue?,
        source: PlexPlaybackSource?,
        queueSourcePreference: PlexPlaybackQueueSourcePreference?,
        at position: TimeInterval,
        autoplay: Bool,
        playbackRate: PlexPlaybackRate,
        videoQualityOverride: PlexVideoQuality?,
        forceVideoTranscode: Bool
    ) {
        automaticallySyncSubtitles = isEnabled
        playbackRequest = TVPlexPlaybackRequest(
            item: item,
            queue: queue,
            source: source,
            queueSourcePreference: queueSourcePreference,
            startTime: PlexPlaybackSeek.clamped(position, duration: item.durationSeconds),
            autoplay: autoplay,
            playbackRate: playbackRate,
            videoQualityOverride: videoQualityOverride,
            forceVideoTranscode: forceVideoTranscode
        )
    }

    func changeSubtitleSize(
        to subtitleSize: PlexSubtitleSize,
        for item: PlexMediaItem,
        queue: PlexPlaybackQueue?,
        source: PlexPlaybackSource?,
        queueSourcePreference: PlexPlaybackQueueSourcePreference?,
        at position: TimeInterval,
        autoplay: Bool,
        playbackRate: PlexPlaybackRate,
        videoQualityOverride: PlexVideoQuality?,
        forceVideoTranscode: Bool
    ) {
        self.subtitleSize = subtitleSize
        playbackRequest = TVPlexPlaybackRequest(
            item: item,
            queue: queue,
            source: source,
            queueSourcePreference: queueSourcePreference,
            startTime: PlexPlaybackSeek.clamped(position, duration: item.durationSeconds),
            autoplay: autoplay,
            playbackRate: playbackRate,
            videoQualityOverride: videoQualityOverride,
            forceVideoTranscode: forceVideoTranscode
        )
    }

    func selectVideoScalingMode(_ scalingMode: PlexVideoScalingMode) {
        videoScalingMode = scalingMode
    }

    func setPlaybackSleepTimer(_ preset: PlexPlaybackSleepTimerPreset) {
        let timer = PlexPlaybackSleepTimer(preset: preset)
        guard timer != playbackSleepTimer else { return }
        playbackSleepTimer = timer
    }

    func clearPlaybackSleepTimer() {
        guard playbackSleepTimer.isActive else { return }
        playbackSleepTimer = .off
    }

    func setPlaybackMarkerBehavior(
        _ behavior: PlexPlaybackMarkerBehavior,
        for kind: PlexPlaybackMarkerKind
    ) {
        switch kind {
        case .intro:
            skipIntroBehavior = behavior
        case .commercial:
            skipAdsBehavior = behavior
        case .credits:
            skipCreditsBehavior = behavior
        }
    }

    func restartPlayback(
        of item: PlexMediaItem,
        queue: PlexPlaybackQueue?,
        source: PlexPlaybackSource? = nil,
        queueSourcePreference: PlexPlaybackQueueSourcePreference? = nil,
        autoplay: Bool = true,
        playbackRate: PlexPlaybackRate = .normal,
        videoQualityOverride: PlexVideoQuality? = nil,
        forceVideoTranscode: Bool = false
    ) {
        playbackRequest = TVPlexPlaybackRequest(
            item: item,
            queue: queue,
            source: source,
            queueSourcePreference: queueSourcePreference,
            startTime: 0,
            autoplay: autoplay,
            playbackRate: playbackRate,
            videoQualityOverride: videoQualityOverride,
            forceVideoTranscode: forceVideoTranscode
        )
    }

    func dismissPlayer() {
        cancelPlaybackPreparation()
        clearPlaybackSleepTimer()
        playbackRequest = nil
    }

    private func cancelPlaybackPreparation() {
        playbackPreparationTask?.cancel()
        playbackPreparationTask = nil
        playbackPreparationID = UUID()
        playbackPreparation = nil
    }

    func artworkURL(path: String?, width: Int, height: Int, usesOriginalImage: Bool = false) async -> URL? {
        guard let connection else { return nil }
        return await client.artworkURL(
            path: path, width: width, height: height,
            connection: connection, usesOriginalImage: usesOriginalImage
        )
    }

    func playbackArtworkData(for item: PlexMediaItem) async -> Data? {
        guard let connection,
              let path = item.nowPlayingArtworkPaths.first else {
            return nil
        }
        return try? await client.fetchArtworkData(
            path: path,
            width: 1_200,
            height: 1_200,
            connection: connection
        )
    }

    func contentProposalArtworkData(for item: PlexMediaItem) async -> Data? {
        guard let connection,
              let path = item.contentProposalArtworkPaths.first else {
            return nil
        }
        return try? await client.fetchArtworkData(
            path: path,
            width: 1_280,
            height: 720,
            connection: connection
        )
    }

    func playbackChapterArtwork(
        for chapters: [PlexPlaybackChapter]
    ) async -> [String: Data] {
        guard let connection else { return [:] }
        let client = client

        let requests = chapters.compactMap { chapter in
            chapter.thumbnailPath.map { path in
                (chapterID: chapter.id, path: path)
            }
        }
        let artwork: [(chapterID: String, data: Data)] = await PlexBoundedConcurrentMap.compactMap(
            requests,
            maximumConcurrentTasks: 4
        ) { request in
            guard let data = try? await client.fetchArtworkData(
                path: request.path,
                width: 640,
                height: 360,
                connection: connection
            ) else {
                return nil
            }
            return (chapterID: request.chapterID, data: data)
        }

        return artwork.reduce(into: [:]) { result, element in
            result[element.chapterID] = element.data
        }
    }

    func playbackPlan(
        for request: TVPlexPlaybackRequest,
        recovery: PlexPlaybackRecoveryRequest? = nil
    ) async throws -> PlexPlaybackPlan {
        guard let connection else { throw TVPlexError.invalidServerURL }
        return try await client.playbackPlan(
            for: request.item,
            startTime: recovery?.startTime ?? request.startTime,
            sessionIdentifier: request.sessionIdentifier,
            videoQuality: recovery?.videoQuality
                ?? request.videoQualityOverride
                ?? activeVideoQuality,
            musicQuality: activeMusicQuality,
            audioBoost: audioBoost,
            streamingPolicy: playbackStreamingPolicy,
            subtitleBurnMode: subtitleBurnMode,
            subtitleSize: subtitleSize,
            automaticallySyncSubtitles: automaticallySyncSubtitles,
            automaticallyAdjustVideoQuality: automaticallyAdjustVideoQuality,
            playSmallerVideosAtOriginalQuality: connection.kind == .local
                || playSmallerVideosAtOriginalQuality,
            forceVideoTranscode: request.forceVideoTranscode,
            source: recovery?.source ?? request.source,
            forceServerMediaSelection: recovery?.forceServerMediaSelection ?? false,
            connection: connection
        )
    }

    private func setVideoQuality(
        _ quality: PlexVideoQuality,
        for connectionKind: PlexConnectionKind?
    ) {
        if connectionKind == .local {
            localVideoQuality = quality
        } else {
            remoteVideoQuality = quality
        }
    }

    func selectMediaStreams(
        partID: Int,
        audioStreamID: Int? = nil,
        subtitleStreamID: Int? = nil,
        for item: PlexMediaItem
    ) async throws -> PlexMediaItem {
        guard let connection else { throw TVPlexError.invalidServerURL }
        try await client.selectMediaStreams(
            partID: partID,
            audioStreamID: audioStreamID,
            subtitleStreamID: subtitleStreamID,
            connection: connection
        )
        return try await client.fetchMetadata(ratingKey: item.ratingKey, connection: connection)
    }

    func setSubtitleOffset(
        streamID: Int,
        milliseconds: Int,
        for item: PlexMediaItem
    ) async throws -> PlexMediaItem {
        guard let connection else { throw TVPlexError.invalidServerURL }
        try await client.setSubtitleOffset(
            streamID: streamID,
            milliseconds: milliseconds,
            connection: connection
        )
        return try await client.fetchMetadata(ratingKey: item.ratingKey, connection: connection)
    }

    func replacePlayback(
        with item: PlexMediaItem,
        queue: PlexPlaybackQueue?,
        source: PlexPlaybackSource?,
        queueSourcePreference: PlexPlaybackQueueSourcePreference?,
        at position: TimeInterval,
        autoplay: Bool,
        playbackRate: PlexPlaybackRate,
        videoQualityOverride: PlexVideoQuality? = nil,
        forceVideoTranscode: Bool = false
    ) {
        playbackRequest = TVPlexPlaybackRequest(
            item: item,
            queue: queue,
            source: source,
            queueSourcePreference: queueSourcePreference,
            startTime: PlexPlaybackSeek.clamped(position, duration: item.durationSeconds),
            autoplay: autoplay,
            playbackRate: playbackRate,
            videoQualityOverride: videoQualityOverride,
            forceVideoTranscode: forceVideoTranscode
        )
    }

    func changePlaybackVersion(
        to source: PlexPlaybackSource,
        for item: PlexMediaItem,
        queue: PlexPlaybackQueue?,
        queueSourcePreference: PlexPlaybackQueueSourcePreference?,
        at position: TimeInterval,
        autoplay: Bool,
        playbackRate: PlexPlaybackRate,
        videoQualityOverride: PlexVideoQuality?,
        forceVideoTranscode: Bool
    ) {
        guard item.playbackSource(mediaIndex: source.mediaIndex) == source else {
            errorMessage = PlexAPIError.noPlayableMedia.localizedDescription
            return
        }
        let updatedQueueSourcePreference: PlexPlaybackQueueSourcePreference?
        if queue?.isCurrentCinemaPreplayItem == true {
            updatedQueueSourcePreference = queueSourcePreference
        } else if queue != nil {
            updatedQueueSourcePreference = PlexPlaybackQueueSourcePreference(
                ratingKey: item.ratingKey,
                source: source
            )
        } else {
            updatedQueueSourcePreference = nil
        }
        replacePlayback(
            with: item,
            queue: queue,
            source: source,
            queueSourcePreference: updatedQueueSourcePreference,
            at: position,
            autoplay: autoplay,
            playbackRate: playbackRate,
            videoQualityOverride: videoQualityOverride,
            forceVideoTranscode: forceVideoTranscode
        )
    }

    func reportPlayback(
        _ update: PlexTimelineUpdate,
        connection: TVPlexConnection
    ) async -> PlexTimelineResponse? {
        guard self.connection == connection else { return nil }
        let response = await client.reportTimeline(update, connection: connection)
        guard self.connection == connection else { return nil }
        // Read server metadata only after the final position report has completed.
        // Dismissing AVKit happens before that asynchronous write finishes.
        if update.state == .stopped, update.continuing == false {
            playbackMetadataRevision = UUID()
            Task { await refreshAll() }
        }
        return response
    }

    func markWatched(_ item: PlexMediaItem) async {
        guard let connection else { return }
        await client.markWatched(item, connection: connection)
        guard self.connection == connection else { return }
        await refreshAll()
    }

    func nextEpisode(after item: PlexMediaItem) async -> PlexMediaItem? {
        guard autoplayNextEpisode,
              item.type?.lowercased() == "episode",
              let connection else {
            return nil
        }
        do {
            return try await client.fetchNextEpisode(after: item, connection: connection)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func resolvedNextEpisode(after item: PlexMediaItem) async -> PlexMediaItem? {
        guard item.type?.lowercased() == "episode",
              let connection,
              let nextItem = try? await client.fetchNextEpisode(
                  after: item,
                  connection: connection
              ) else {
            return nil
        }
        return try? await client.fetchMetadata(
            ratingKey: nextItem.ratingKey,
            connection: connection
        )
    }

    func preparedQueueAdvance(
        from request: TVPlexPlaybackRequest,
        direction: PlexPlaybackQueueDirection,
        autoplay: Bool,
        playbackRate: PlexPlaybackRate
    ) async throws -> TVPlexPlaybackRequest {
        guard let connection,
              var queue = request.queue,
              queue.canMove(direction) else {
            throw PlexAPIError.invalidPlayQueue
        }
        if queue.needsWindowRefresh(for: direction) {
            guard let currentQueueItemID = queue.currentItem.playQueueItemID else {
                throw PlexAPIError.invalidPlayQueue
            }
            let page = try await client.fetchPlayQueuePage(
                queueID: queue.id,
                centeredOn: currentQueueItemID,
                connection: connection
            )
            try queue.replaceWindow(
                with: page,
                centeredOn: currentQueueItemID
            )
        }
        guard let queuedItem = queue.move(direction) else {
            throw PlexAPIError.invalidPlayQueue
        }
        let item = try await client.fetchMetadata(
            ratingKey: queuedItem.ratingKey,
            connection: connection
        )
        return TVPlexPlaybackRequest(
            item: item,
            queue: queue,
            source: request.queueSourcePreference?.source(for: item),
            queueSourcePreference: request.queueSourcePreference,
            startTime: !queue.isCinemaPreplayQueue && direction == .next
                ? item.resumeSeconds
                : 0,
            autoplay: autoplay,
            playbackRate: playbackRate,
            videoQualityOverride: request.videoQualityOverride,
            forceVideoTranscode: request.forceVideoTranscode
        )
    }

    func preparedQueueSelection(
        from request: TVPlexPlaybackRequest,
        playQueueItemID: String,
        autoplay: Bool,
        playbackRate: PlexPlaybackRate
    ) async throws -> TVPlexPlaybackRequest {
        guard let connection,
              var queue = request.queue,
              queue.presentation.upcomingItems.contains(where: {
                  $0.playQueueItemID == playQueueItemID
              }),
              let queuedItem = queue.move(toPlayQueueItemID: playQueueItemID) else {
            throw PlexAPIError.invalidPlayQueue
        }
        let item = try await client.fetchMetadata(
            ratingKey: queuedItem.ratingKey,
            connection: connection
        )
        return TVPlexPlaybackRequest(
            item: item,
            queue: queue,
            source: request.queueSourcePreference?.source(for: item),
            queueSourcePreference: request.queueSourcePreference,
            startTime: queue.isCinemaPreplayQueue ? 0 : item.resumeSeconds,
            autoplay: autoplay,
            playbackRate: playbackRate,
            videoQualityOverride: request.videoQualityOverride,
            forceVideoTranscode: request.forceVideoTranscode
        )
    }

    func playbackRequest(
        bySettingQueueShuffled shuffled: Bool,
        from request: TVPlexPlaybackRequest
    ) async throws -> TVPlexPlaybackRequest {
        guard let connection,
              var queue = request.queue,
              queue.canChangeShuffle,
              queue.isShuffled != shuffled else {
            throw PlexAPIError.invalidPlayQueue
        }
        let page = try await client.setPlayQueueShuffled(
            shuffled,
            queueID: queue.id,
            connection: connection
        )
        try queue.applyShuffleMutation(page, expectedShuffled: shuffled)
        return request.withQueue(queue)
    }

    func playbackRequest(
        byRemovingQueueItem playQueueItemID: String,
        from request: TVPlexPlaybackRequest
    ) async throws -> TVPlexPlaybackRequest {
        guard let connection,
              var queue = request.queue,
              queue.canRemoveUpcomingItem(playQueueItemID: playQueueItemID) else {
            throw PlexAPIError.invalidPlayQueue
        }
        let page = try await client.removePlayQueueItem(
            queueID: queue.id,
            playQueueItemID: playQueueItemID,
            connection: connection
        )
        try queue.applyRemoval(
            page,
            removedPlayQueueItemID: playQueueItemID
        )
        return request.withQueue(queue)
    }

    func playbackRequest(
        byMovingQueueItem playQueueItemID: String,
        direction: PlexPlayQueueItemMoveDirection,
        from request: TVPlexPlaybackRequest
    ) async throws -> TVPlexPlaybackRequest {
        guard let connection,
              var queue = request.queue,
              let move = queue.moveRequest(
                  for: playQueueItemID,
                  direction: direction
              ) else {
            throw PlexAPIError.invalidPlayQueue
        }
        let page = try await client.movePlayQueueItem(
            queueID: queue.id,
            move: move,
            connection: connection
        )
        try queue.applyMove(page, request: move)
        return request.withQueue(queue)
    }

    func preparedRepeatedQueue(
        from request: TVPlexPlaybackRequest,
        playbackRate: PlexPlaybackRate
    ) async throws -> TVPlexPlaybackRequest {
        guard let connection,
              var queue = request.queue,
              queue.canRepeatAll else {
            throw PlexAPIError.invalidPlayQueue
        }
        let page = try await client.resetPlayQueue(
            queueID: queue.id,
            connection: connection
        )
        try queue.applyReset(page)
        let item = try await client.fetchMetadata(
            ratingKey: queue.currentItem.ratingKey,
            connection: connection
        )
        return TVPlexPlaybackRequest(
            item: item,
            queue: queue,
            source: request.queueSourcePreference?.source(for: item),
            queueSourcePreference: request.queueSourcePreference,
            startTime: 0,
            playbackRate: playbackRate,
            videoQualityOverride: request.videoQualityOverride,
            forceVideoTranscode: request.forceVideoTranscode
        )
    }

    func preparedNextPlayback(
        after request: TVPlexPlaybackRequest,
        playbackRate: PlexPlaybackRate
    ) async throws -> TVPlexPlaybackRequest? {
        if request.queue?.canMoveNext == true {
            return try await preparedQueueAdvance(
                from: request,
                direction: .next,
                autoplay: true,
                playbackRate: playbackRate
            )
        }
        guard request.queue == nil,
              request.item.type?.lowercased() == "episode",
              let connection,
              let nextItem = try await client.fetchNextEpisode(
                  after: request.item,
                  connection: connection
              ) else {
            return nil
        }
        let item = try await client.fetchMetadata(
            ratingKey: nextItem.ratingKey,
            connection: connection
        )
        return TVPlexPlaybackRequest(
            item: item,
            source: request.queueSourcePreference?.source(for: item),
            queueSourcePreference: request.queueSourcePreference,
            startTime: item.resumeSeconds,
            playbackRate: playbackRate,
            videoQualityOverride: request.videoQualityOverride,
            forceVideoTranscode: request.forceVideoTranscode
        )
    }

    private func resetLibraries() {
        libraries = []
        libraryItems = [:]
        libraryTotalSizes = [:]
        libraryErrors = [:]
        libraryQueries = [:]
        libraryRequestIDs = [:]
        libraryNextOffsets = [:]
        libraryPaginationFailureIDs = []
    }

    func logout() async {
        accountJWTManager.invalidatePreparation()
        sessionRevision = UUID()
        let revision = sessionRevision
        availableServers = []
        pendingTopShelfRoute = nil
        topShelfRouteTask?.cancel()
        topShelfPublisher.clear()
        connection = nil
        searchTask?.cancel()
        signInTask?.cancel()
        accountTokenRefreshTask?.cancel()
        cancelPlaybackPreparation()
        do {
            try await accountStorage.persistAccountToken("")
            try requireCurrentSession(revision)
            try await keychain.delete(account: KeychainAccounts.serverToken)
        } catch {
            guard revision == sessionRevision, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        guard revision == sessionRevision, !Task.isCancelled else { return }
        defaults.removeObject(forKey: DefaultsKey.selectedServerIdentifier)
        connection = nil
        connectionState = .disconnected
        homeHubs = []
        resetLibraries()
        searchHubs = []
        searchErrorMessage = nil
        clearPlaybackSleepTimer()
        playbackRequest = nil
        signInCode = nil
        availableServers = []
        isPairing = false
        startPlexDeviceAuthorization()
    }

    func openTopShelfURL(_ url: URL) {
        guard let route = TVTopShelfRoute(url: url) else {
            errorMessage = "This PlexBar content link is invalid."
            return
        }
        topShelfRouteTask?.cancel()
        pendingTopShelfRoute = route
        processPendingTopShelfRoute()
    }

    private func processPendingTopShelfRoute() {
        guard hasRestoredSession, let route = pendingTopShelfRoute else { return }
        guard let connection else {
            // Keep the route while the saved session reconnects or the server picker is visible.
            if !hasAuthorizedAccount {
                pendingTopShelfRoute = nil
                errorMessage = "Sign in to Plex to open this title."
            }
            return
        }
        pendingTopShelfRoute = nil
        guard route.serverIdentifier == connection.serverIdentifier else {
            errorMessage = "This title belongs to a different Plex server. Select that server and open the title again."
            return
        }
        selectedTab = .home
        topShelfRouteTask = Task {
            do {
                let item = try await client.fetchMetadata(ratingKey: route.ratingKey, connection: connection)
                try Task.checkCancellation()
                guard self.connection == connection else { return }
                guard item.ratingKey == route.ratingKey else { throw TVPlexError.invalidResponse }
                homePath = [.media(item)]
                switch route.action {
                case .display:
                    dismissPlayer()
                case .play:
                    play(item, resume: true)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.connection == connection else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func fetchAuthorizedServers() async throws -> [PlexServerResource] {
        let servers = try await performAccountRequest { token in
            try await authClient.fetchServers(
                userToken: token,
                clientContext: PlexClientContext(
                    clientIdentifier: accountStorage.clientIdentifier
                )
            )
        }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        guard !servers.isEmpty else {
            throw PlexAuthError.noServersFound
        }
        return servers
    }

    private func initialPlaybackRequest(
        for item: PlexMediaItem,
        source requestedSource: PlexPlaybackSource?,
        resume: Bool,
        playbackRate: PlexPlaybackRate
    ) async throws -> TVPlexPlaybackRequest {
        guard let connection else { throw TVPlexError.invalidServerURL }
        let resolvedItem = try await client.fetchMetadata(
            ratingKey: item.ratingKey,
            connection: connection
        )
        let source: PlexPlaybackSource?
        if let requestedSource {
            guard resolvedItem.playbackSource(
                mediaIndex: requestedSource.mediaIndex
            ) == requestedSource else {
                throw PlexAPIError.noPlayableMedia
            }
            source = requestedSource
        } else {
            source = nil
        }
        let startOption: PlexPlaybackStartOption = resume && resolvedItem.resumeSeconds > 0
            ? .resume
            : .beginning
        let cinemaExtrasPrefixCount = PlexCinemaPreplayRequestPolicy.extrasPrefixCount(
            for: resolvedItem,
            startOption: startOption,
            preference: cinemaPreplayPreference
        )
        let queue: PlexPlaybackQueue?
        if let cinemaExtrasPrefixCount {
            queue = try await client.createCinemaPlayQueue(
                for: resolvedItem,
                extrasPrefixCount: cinemaExtrasPrefixCount,
                connection: connection
            )
        } else if resolvedItem.continuousPlayQueueType != nil {
            queue = try await client.createContinuousPlayQueue(
                for: resolvedItem,
                connection: connection
            )
        } else {
            queue = nil
        }
        let playbackItem: PlexMediaItem
        if let queue, queue.isCurrentCinemaPreplayItem || resolvedItem.supportsHierarchyPlayback {
            playbackItem = try await client.fetchMetadata(
                ratingKey: queue.currentItem.ratingKey,
                connection: connection
            )
        } else {
            playbackItem = resolvedItem
        }
        guard playbackItem.isPlayable else { throw PlexAPIError.noPlayableMedia }
        return TVPlexPlaybackRequest(
            item: playbackItem,
            queue: queue,
            source: playbackItem.ratingKey == resolvedItem.ratingKey ? source : nil,
            queueSourcePreference: source.map {
                PlexPlaybackQueueSourcePreference(
                    ratingKey: resolvedItem.ratingKey,
                    source: $0
                )
            },
            startTime: resume && queue?.isCurrentCinemaPreplayItem != true
                ? playbackItem.resumeSeconds
                : 0,
            playbackRate: playbackRate
        )
    }

    private func primaryExtraPlaybackRequest(
        path: String
    ) async throws -> TVPlexPlaybackRequest {
        guard let connection else { throw TVPlexError.invalidServerURL }
        let extra = try await client.fetchMetadata(
            path: path,
            connection: connection
        )
        guard extra.isPlayable else {
            throw PlexAPIError.noPlayableMedia
        }
        return TVPlexPlaybackRequest(
            item: extra,
            startTime: 0
        )
    }

    private func presentDiscoveredServers(
        _ servers: [PlexServerResource],
        preferStoredSelection: Bool,
        revision: UUID
    ) async {
        guard revision == sessionRevision, hasAuthorizedAccount, !Task.isCancelled else { return }
        availableServers = servers
        if preferStoredSelection,
           let selectedServerIdentifier = defaults.string(
               forKey: DefaultsKey.selectedServerIdentifier
           )?.nilIfBlank,
           let selectedServer = servers.first(where: { $0.id == selectedServerIdentifier }) {
            await selectServer(selectedServer)
        } else if servers.count == 1, let server = servers.first {
            await selectServer(server)
        } else {
            connection = nil
            connectionState = .disconnected
            availableServers = servers
        }
    }

    private func requireCurrentSession(_ revision: UUID) throws {
        try Task.checkCancellation()
        guard revision == sessionRevision else { throw CancellationError() }
    }

    private func performAccountRequest<Value>(
        _ operation: (String) async throws -> Value
    ) async throws -> Value {
        let revision = sessionRevision
        let preparedToken = try await accountJWTManager.prepareAccountToken()
        try requireCurrentSession(revision)
        scheduleAccountTokenRefresh(preparedToken)

        do {
            let result = try await operation(preparedToken.token)
            try requireCurrentSession(revision)
            return result
        } catch let error as PlexAuthError where error.requiresTokenRefresh {
            try requireCurrentSession(revision)
            let refreshedToken = try await accountJWTManager.recoverRejectedAccountToken(preparedToken.token)
            try requireCurrentSession(revision)
            scheduleAccountTokenRefresh(refreshedToken)
            do {
                let result = try await operation(refreshedToken.token)
                try requireCurrentSession(revision)
                return result
            } catch let retryError as PlexAuthError where retryError.requiresTokenRefresh {
                try requireCurrentSession(revision)
                if accountStorage.storedAccountToken == refreshedToken.token {
                    await logout()
                }
                throw retryError
            }
        }
    }

    private func scheduleAccountTokenRefresh(_ preparedToken: PlexPreparedAccountToken) {
        let revision = sessionRevision
        accountTokenRefreshTask?.cancel()
        let delay = max(preparedToken.refreshAt.timeIntervalSinceNow, 0)
        accountTokenRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self else { return }

            do {
                let refreshedToken = try await accountJWTManager.prepareAccountToken(
                    forceRefresh: true
                )
                try requireCurrentSession(revision)
                scheduleAccountTokenRefresh(refreshedToken)
            } catch {
                guard revision == sessionRevision, !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}
