import Foundation
import Observation

@MainActor
@Observable
final class PlexSettingsStore {
    private enum DefaultsKeys {
        static let installIdentifier = "plex.installIdentifier"
        static let cachedConnectionURL = "plex.serverURL"
        static let cachedConnectionKind = "plex.cachedConnectionKind"
        static let clientIdentifier = "plex.clientIdentifier"
        static let selectedServerIdentifier = "plex.selectedServerIdentifier"
        static let selectedServerName = "plex.selectedServerName"
        static let connectionRecheckIntervalSeconds = "plex.connectionRecheckIntervalSeconds"
        static let historyPollIntervalSeconds = "plex.historyPollIntervalSeconds"
        static let localVideoQuality = "plex.localVideoQuality"
        static let remoteVideoQuality = "plex.remoteVideoQuality"
        static let downloadVideoQuality = "plex.downloadVideoQuality"
        static let downloadMusicQuality = "plex.downloadMusicQuality"
        static let downloadSubtitlePreference = "plex.downloadSubtitlePreference"
        static let qualitySuggestionsEnabled = "plex.qualitySuggestionsEnabled"
        static let allowsDirectPlay = "plex.allowsDirectPlay"
        static let allowsDirectStream = "plex.allowsDirectStream"
        static let forceDirectPlay = "plex.forceDirectPlay"
        static let videoDynamicRange = "plex.videoDynamicRange"
        static let videoScalingMode = "plex.videoScalingMode"
        static let episodeSpoilerPolicy = "plex.episodeSpoilerPolicy"
        static let autoplayUpNext = "plex.autoplayUpNext"
        static let autoplayCountdown = "plex.autoplayCountdown"
        static let passoutProtection = "plex.passoutProtection"
        static let cinemaPreplayPreference = "plex.cinemaPreplayPreference"
        static let rewindOnResumeSeconds = "plex.rewindOnResumeSeconds"
        static let skipIntroBehavior = "plex.skipIntroBehavior"
        static let skipAdsBehavior = "plex.skipAdsBehavior"
        static let skipCreditsBehavior = "plex.skipCreditsBehavior"
        static let registeredJWTKeyID = "plex.registeredJWTKeyID"
    }

    private let defaults: UserDefaults
    private let credentialStore: any PlexCredentialPersisting
    private let loginItemService: any PlexLoginItemControlling
    private var credentialLoadingTask: Task<PlexStoredCredentials, Error>?
    private var credentialPersistenceTask: Task<Void, Error>?
    private var credentialPersistenceErrors: [String: Error] = [:]
    private var isApplyingLoadedCredentials = false

    var cachedConnectionURLString: String {
        didSet {
            defaults.set(cachedConnectionURLString, forKey: DefaultsKeys.cachedConnectionURL)
        }
    }

    var cachedConnectionKind: PlexConnectionKind? {
        didSet {
            defaults.set(cachedConnectionKind?.rawValue, forKey: DefaultsKeys.cachedConnectionKind)
        }
    }

    var selectedServerIdentifier: String? {
        didSet {
            defaults.set(selectedServerIdentifier, forKey: DefaultsKeys.selectedServerIdentifier)
        }
    }

    var selectedServerName: String? {
        didSet {
            defaults.set(selectedServerName, forKey: DefaultsKeys.selectedServerName)
        }
    }

    var userToken: String {
        didSet {
            persistUserToken()
        }
    }

    var serverToken: String {
        didSet {
            persistServerToken()
        }
    }

    var connectionRecheckIntervalSeconds: Int {
        didSet {
            let normalizedValue = Self.normalizedConnectionRecheckIntervalSeconds(connectionRecheckIntervalSeconds)
            if connectionRecheckIntervalSeconds != normalizedValue {
                connectionRecheckIntervalSeconds = normalizedValue
                return
            }

            defaults.set(normalizedValue, forKey: DefaultsKeys.connectionRecheckIntervalSeconds)
        }
    }

    var historyPollIntervalSeconds: Int {
        didSet {
            let normalizedValue = Self.normalizedHistoryPollIntervalSeconds(historyPollIntervalSeconds)
            if historyPollIntervalSeconds != normalizedValue {
                historyPollIntervalSeconds = normalizedValue
                return
            }

            defaults.set(normalizedValue, forKey: DefaultsKeys.historyPollIntervalSeconds)
        }
    }

    var localVideoQuality: PlexVideoQuality {
        didSet {
            defaults.set(localVideoQuality.rawValue, forKey: DefaultsKeys.localVideoQuality)
        }
    }

    var remoteVideoQuality: PlexVideoQuality {
        didSet {
            defaults.set(remoteVideoQuality.rawValue, forKey: DefaultsKeys.remoteVideoQuality)
        }
    }

    var downloadVideoQuality: PlexDownloadVideoQuality {
        didSet {
            defaults.set(downloadVideoQuality.rawValue, forKey: DefaultsKeys.downloadVideoQuality)
        }
    }

    var downloadMusicQuality: PlexMusicQuality {
        didSet {
            defaults.set(downloadMusicQuality.rawValue, forKey: DefaultsKeys.downloadMusicQuality)
        }
    }

    var downloadSubtitlePreference: PlexDownloadSubtitlePreference {
        didSet {
            defaults.set(
                downloadSubtitlePreference.rawValue,
                forKey: DefaultsKeys.downloadSubtitlePreference
            )
        }
    }

    var qualitySuggestionsEnabled: Bool {
        didSet {
            defaults.set(qualitySuggestionsEnabled, forKey: DefaultsKeys.qualitySuggestionsEnabled)
        }
    }

    var allowsDirectPlay: Bool {
        didSet {
            defaults.set(allowsDirectPlay, forKey: DefaultsKeys.allowsDirectPlay)
        }
    }

    var allowsDirectStream: Bool {
        didSet {
            defaults.set(allowsDirectStream, forKey: DefaultsKeys.allowsDirectStream)
        }
    }

    var forceDirectPlay: Bool {
        didSet {
            defaults.set(forceDirectPlay, forKey: DefaultsKeys.forceDirectPlay)
        }
    }

    var videoDynamicRange: PlexVideoDisplayDynamicRange {
        didSet {
            defaults.set(videoDynamicRange.rawValue, forKey: DefaultsKeys.videoDynamicRange)
        }
    }

    var videoScalingMode: PlexVideoScalingMode {
        didSet {
            defaults.set(videoScalingMode.rawValue, forKey: DefaultsKeys.videoScalingMode)
        }
    }

    var episodeSpoilerPolicy: PlexEpisodeSpoilerPolicy {
        didSet {
            defaults.set(episodeSpoilerPolicy.rawValue, forKey: DefaultsKeys.episodeSpoilerPolicy)
        }
    }

    var autoplayUpNext: Bool {
        didSet {
            defaults.set(autoplayUpNext, forKey: DefaultsKeys.autoplayUpNext)
        }
    }

    var autoplayCountdown: PlexAutoplayCountdown {
        didSet {
            defaults.set(autoplayCountdown.rawValue, forKey: DefaultsKeys.autoplayCountdown)
        }
    }

    var passoutProtection: PlexPassoutProtection {
        didSet {
            defaults.set(passoutProtection.rawValue, forKey: DefaultsKeys.passoutProtection)
        }
    }

    var cinemaPreplayPreference: PlexCinemaPreplayPreference {
        didSet {
            defaults.set(
                cinemaPreplayPreference.rawValue,
                forKey: DefaultsKeys.cinemaPreplayPreference
            )
        }
    }

    var rewindOnResume: PlexRewindOnResume {
        didSet {
            defaults.set(rewindOnResume.seconds, forKey: DefaultsKeys.rewindOnResumeSeconds)
        }
    }

    var skipIntroBehavior: PlexPlaybackMarkerBehavior {
        didSet {
            defaults.set(skipIntroBehavior.rawValue, forKey: DefaultsKeys.skipIntroBehavior)
        }
    }

    var skipAdsBehavior: PlexPlaybackMarkerBehavior {
        didSet {
            defaults.set(skipAdsBehavior.rawValue, forKey: DefaultsKeys.skipAdsBehavior)
        }
    }

    var skipCreditsBehavior: PlexPlaybackMarkerBehavior {
        didSet {
            defaults.set(skipCreditsBehavior.rawValue, forKey: DefaultsKeys.skipCreditsBehavior)
        }
    }

    private(set) var clientIdentifier: String {
        didSet {
            defaults.set(clientIdentifier, forKey: DefaultsKeys.clientIdentifier)
        }
    }

    private(set) var registeredJWTKeyID: String? {
        didSet {
            defaults.set(registeredJWTKeyID, forKey: DefaultsKeys.registeredJWTKeyID)
        }
    }

    private(set) var openAtLoginStatus: PlexLoginItemStatus
    private(set) var hasLoadedCredentials: Bool
    private(set) var isLoadingCredentials = false
    private(set) var credentialLoadingErrorMessage: String?
    private(set) var credentialPersistenceErrorMessage: String?
    var openAtLoginErrorMessage: String?

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainStore = KeychainStore(service: AppConstants.bundleIdentifier),
        loginItemService: any PlexLoginItemControlling = PlexLoginItemService(),
        credentialStore: (any PlexCredentialPersisting)? = nil,
        initialCredentials: PlexStoredCredentials? = nil
    ) {
        self.defaults = defaults
        if let credentialStore {
            self.credentialStore = credentialStore
        } else if let initialCredentials {
            self.credentialStore = PlexMemoryCredentialStore(credentials: initialCredentials)
        } else {
            self.credentialStore = PlexKeychainCredentialStore(keychain: keychain)
        }
        self.loginItemService = loginItemService
        cachedConnectionURLString = defaults.string(forKey: DefaultsKeys.cachedConnectionURL) ?? ""
        cachedConnectionKind = defaults.string(forKey: DefaultsKeys.cachedConnectionKind)
            .flatMap(PlexConnectionKind.init(rawValue:))

        let installIdentifier = Self.loadInstallIdentifier(from: defaults)
        clientIdentifier = Self.loadClientIdentifier(from: defaults, installIdentifier: installIdentifier)
        registeredJWTKeyID = defaults.string(forKey: DefaultsKeys.registeredJWTKeyID)?.nilIfBlank

        selectedServerIdentifier = defaults.string(forKey: DefaultsKeys.selectedServerIdentifier)
        selectedServerName = defaults.string(forKey: DefaultsKeys.selectedServerName)
        userToken = initialCredentials?.userToken ?? ""
        serverToken = initialCredentials?.serverToken ?? ""
        hasLoadedCredentials = initialCredentials != nil
        connectionRecheckIntervalSeconds = Self.normalizedConnectionRecheckIntervalSeconds(
            defaults.object(forKey: DefaultsKeys.connectionRecheckIntervalSeconds) as? Int
                ?? AppConstants.defaultConnectionRecheckIntervalSeconds
        )
        historyPollIntervalSeconds = Self.normalizedHistoryPollIntervalSeconds(
            defaults.object(forKey: DefaultsKeys.historyPollIntervalSeconds) as? Int
                ?? AppConstants.defaultHistoryPollIntervalSeconds
        )
        localVideoQuality = defaults.string(forKey: DefaultsKeys.localVideoQuality)
            .flatMap(PlexVideoQuality.init(rawValue:)) ?? .original
        remoteVideoQuality = defaults.string(forKey: DefaultsKeys.remoteVideoQuality)
            .flatMap(PlexVideoQuality.init(rawValue:)) ?? .original
        downloadVideoQuality = defaults.string(forKey: DefaultsKeys.downloadVideoQuality)
            .flatMap(PlexDownloadVideoQuality.init(rawValue:)) ?? .original
        downloadMusicQuality = defaults.string(forKey: DefaultsKeys.downloadMusicQuality)
            .flatMap(PlexMusicQuality.init(rawValue:)) ?? .original
        downloadSubtitlePreference = defaults.string(
            forKey: DefaultsKeys.downloadSubtitlePreference
        ).flatMap(PlexDownloadSubtitlePreference.init(rawValue:)) ?? .selectable
        qualitySuggestionsEnabled =
            defaults.object(forKey: DefaultsKeys.qualitySuggestionsEnabled) as? Bool ?? true
        allowsDirectPlay = defaults.object(forKey: DefaultsKeys.allowsDirectPlay) as? Bool ?? true
        allowsDirectStream = defaults.object(forKey: DefaultsKeys.allowsDirectStream) as? Bool ?? true
        forceDirectPlay = defaults.object(forKey: DefaultsKeys.forceDirectPlay) as? Bool ?? false
        videoDynamicRange = defaults.string(forKey: DefaultsKeys.videoDynamicRange)
            .flatMap(PlexVideoDisplayDynamicRange.init(rawValue:)) ?? .automatic
        videoScalingMode = defaults.string(forKey: DefaultsKeys.videoScalingMode)
            .flatMap(PlexVideoScalingMode.init(rawValue:)) ?? .fit
        episodeSpoilerPolicy = defaults.string(forKey: DefaultsKeys.episodeSpoilerPolicy)
            .flatMap(PlexEpisodeSpoilerPolicy.init(rawValue:)) ?? .off
        autoplayUpNext = defaults.object(forKey: DefaultsKeys.autoplayUpNext) as? Bool ?? true
        autoplayCountdown = (defaults.object(forKey: DefaultsKeys.autoplayCountdown) as? Int)
            .flatMap(PlexAutoplayCountdown.init(rawValue:)) ?? .tenSeconds
        passoutProtection = (defaults.object(forKey: DefaultsKeys.passoutProtection) as? Int)
            .flatMap(PlexPassoutProtection.init(rawValue:)) ?? .twoHours
        cinemaPreplayPreference = (
            defaults.object(forKey: DefaultsKeys.cinemaPreplayPreference) as? Int
        ).flatMap(PlexCinemaPreplayPreference.init(rawValue:)) ?? .off
        rewindOnResume = PlexRewindOnResume(
            seconds: defaults.object(forKey: DefaultsKeys.rewindOnResumeSeconds) as? Int ?? 0
        )
        skipIntroBehavior = defaults.string(forKey: DefaultsKeys.skipIntroBehavior)
            .flatMap(PlexPlaybackMarkerBehavior.init(rawValue:)) ?? .manually
        skipAdsBehavior = defaults.string(forKey: DefaultsKeys.skipAdsBehavior)
            .flatMap(PlexPlaybackMarkerBehavior.init(rawValue:)) ?? .manually
        skipCreditsBehavior = defaults.string(forKey: DefaultsKeys.skipCreditsBehavior)
            .flatMap(PlexPlaybackMarkerBehavior.init(rawValue:)) ?? .manually
        openAtLoginStatus = loginItemService.status()
        credentialLoadingErrorMessage = nil
        credentialPersistenceErrorMessage = nil
        openAtLoginErrorMessage = nil
    }

    var normalizedServerURL: URL? {
        PlexURLBuilder.normalizeServerURL(cachedConnectionURLString)
    }

    var trimmedUserToken: String {
        userToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedServerToken: String {
        serverToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasValidConfiguration: Bool {
        selectedServerIdentifier?.nilIfBlank != nil && !trimmedServerToken.isEmpty
    }

    var hasAuthenticatedAccount: Bool {
        !trimmedUserToken.isEmpty
    }

    var autoplayPreferences: PlexAutoplayPreferences {
        PlexAutoplayPreferences(
            isEnabled: autoplayUpNext,
            countdown: autoplayCountdown,
            passoutProtection: passoutProtection
        )
    }

    var playbackStreamingPolicy: PlexPlaybackStreamingPolicy {
        PlexPlaybackStreamingPolicy(
            allowsDirectPlay: allowsDirectPlay,
            allowsDirectStream: allowsDirectStream,
            forceDirectPlay: forceDirectPlay
        )
    }

    var downloadPreferences: PlexDownloadPreferences {
        PlexDownloadPreferences(
            videoQuality: downloadVideoQuality,
            musicQuality: downloadMusicQuality,
            subtitlePreference: downloadSubtitlePreference
        )
    }

    var playbackMarkerPreferences: PlexPlaybackMarkerPreferences {
        PlexPlaybackMarkerPreferences(
            intro: skipIntroBehavior,
            ads: skipAdsBehavior,
            credits: skipCreditsBehavior
        )
    }

    var opensAtLogin: Bool {
        switch openAtLoginStatus {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        }
    }

    var openAtLoginRequiresApproval: Bool {
        openAtLoginStatus == .requiresApproval
    }

    func saveAuthenticatedUserToken(_ token: String) async throws {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousToken = trimmedUserToken
        try Task.checkCancellation()
        let persistenceTask = enqueueCredentialPersistence(
            normalizedToken.nilIfBlank,
            account: KeychainAccounts.userToken
        )
        try await persistenceTask.value

        do {
            try Task.checkCancellation()
        } catch {
            let rollbackTask = enqueueCredentialPersistence(
                previousToken.nilIfBlank,
                account: KeychainAccounts.userToken
            )
            try? await rollbackTask.value
            throw error
        }

        guard userToken != normalizedToken else { return }
        isApplyingLoadedCredentials = true
        userToken = normalizedToken
        isApplyingLoadedCredentials = false
    }

    func saveServerSelection(_ server: PlexServerResource) {
        selectedServerIdentifier = server.id
        selectedServerName = server.name
        if serverToken != server.accessToken {
            serverToken = server.accessToken
        }
        clearCachedConnection()
    }

    func saveResolvedConnection(_ connection: PlexResolvedConnection) {
        cachedConnectionURLString = connection.url.absoluteString
        cachedConnectionKind = connection.kind
    }

    func clearCachedConnection() {
        cachedConnectionURLString = ""
        cachedConnectionKind = nil
    }

    func clearAuthentication() {
        selectedServerIdentifier = nil
        selectedServerName = nil
        clearCachedConnection()
        userToken = ""
        serverToken = ""
    }

    func markJWTKeyRegistered(keyID: String) {
        guard let keyID = keyID.nilIfBlank,
              registeredJWTKeyID != keyID else {
            return
        }
        registeredJWTKeyID = keyID
    }

    func refreshOpenAtLoginStatus() {
        openAtLoginStatus = loginItemService.status()
        openAtLoginErrorMessage = nil
    }

    func setOpenAtLogin(_ enabled: Bool) {
        openAtLoginErrorMessage = nil

        do {
            try loginItemService.setEnabled(enabled)
            refreshOpenAtLoginStatus()

            if enabled && openAtLoginStatus == .notFound {
                openAtLoginErrorMessage = "PlexBar could not register itself as a login item."
            }
        } catch {
            refreshOpenAtLoginStatus()
            openAtLoginErrorMessage = openAtLoginActionErrorMessage(for: enabled, error: error)
        }
    }

    func openLoginItemsSystemSettings() {
        loginItemService.openSystemSettingsLoginItems()
    }

    private func openAtLoginActionErrorMessage(for enabled: Bool, error: Error) -> String {
        let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription

        if enabled {
            return "PlexBar could not enable Open at Login. \(description)"
        }

        return "PlexBar could not disable Open at Login. \(description)"
    }

    private static func normalizedConnectionRecheckIntervalSeconds(_ value: Int) -> Int {
        guard AppConstants.allowedConnectionRecheckIntervalSeconds.contains(value) else {
            return AppConstants.defaultConnectionRecheckIntervalSeconds
        }

        return value
    }

    private static func normalizedHistoryPollIntervalSeconds(_ value: Int) -> Int {
        guard AppConstants.allowedHistoryPollIntervalSeconds.contains(value) else {
            return AppConstants.defaultHistoryPollIntervalSeconds
        }

        return value
    }

    private static func loadInstallIdentifier(from defaults: UserDefaults) -> String {
        if let existingInstallIdentifier = defaults.string(forKey: DefaultsKeys.installIdentifier)?.nilIfBlank {
            return existingInstallIdentifier
        }

        let installIdentifier = defaults.string(forKey: DefaultsKeys.clientIdentifier)?.nilIfBlank ?? newIdentifier()
        defaults.set(installIdentifier, forKey: DefaultsKeys.installIdentifier)
        return installIdentifier
    }

    private static func loadClientIdentifier(from defaults: UserDefaults, installIdentifier: String) -> String {
        if let existingClientIdentifier = defaults.string(forKey: DefaultsKeys.clientIdentifier)?.nilIfBlank {
            return existingClientIdentifier
        }

        defaults.set(installIdentifier, forKey: DefaultsKeys.clientIdentifier)
        return installIdentifier
    }

    private static func newIdentifier() -> String {
        UUID().uuidString
    }
}

extension PlexSettingsStore: PlexAccountJWTStorage {
    var storedAccountToken: String {
        trimmedUserToken
    }

    func persistAccountToken(_ token: String) async throws {
        try await saveAuthenticatedUserToken(token)
    }
}

private extension PlexSettingsStore {
    func persistUserToken() {
        guard !isApplyingLoadedCredentials else {
            return
        }
        enqueueCredentialPersistence(trimmedUserToken.nilIfBlank, account: KeychainAccounts.userToken)
    }

    func persistServerToken() {
        guard !isApplyingLoadedCredentials else {
            return
        }
        enqueueCredentialPersistence(trimmedServerToken.nilIfBlank, account: KeychainAccounts.serverToken)
    }

    @discardableResult
    func enqueueCredentialPersistence(
        _ value: String?,
        account: String
    ) -> Task<Void, Error> {
        let previousTask = credentialPersistenceTask
        let credentialStore = credentialStore
        let task = Task { @MainActor [weak self] in
            _ = try? await previousTask?.value
            do {
                try await credentialStore.replace(value, account: account)
                self?.recordCredentialPersistenceSuccess(account: account)
            } catch {
                self?.recordCredentialPersistenceFailure(error, account: account)
                throw error
            }
        }
        credentialPersistenceTask = task
        return task
    }
}

extension PlexSettingsStore {
    func loadCredentials() async {
        guard !hasLoadedCredentials else {
            return
        }

        if let credentialLoadingTask {
            await finishCredentialLoad(credentialLoadingTask)
            return
        }

        let credentialStore = credentialStore
        let loadingTask = Task {
            try await credentialStore.loadCredentials()
        }
        credentialLoadingTask = loadingTask
        isLoadingCredentials = true
        credentialLoadingErrorMessage = nil
        await finishCredentialLoad(loadingTask)
    }

    func waitForCredentialPersistence() async throws {
        try await credentialPersistenceTask?.value
        if let error = credentialPersistenceErrors
            .sorted(by: { $0.key < $1.key })
            .first?.value {
            throw error
        }
    }

    private func finishCredentialLoad(_ task: Task<PlexStoredCredentials, Error>) async {
        do {
            apply(try await task.value)
        } catch {
            hasLoadedCredentials = false
            isLoadingCredentials = false
            credentialLoadingTask = nil
            credentialLoadingErrorMessage = Self.credentialErrorMessage(error)
        }
    }

    private func apply(_ credentials: PlexStoredCredentials) {
        guard !hasLoadedCredentials else {
            return
        }

        isApplyingLoadedCredentials = true
        userToken = credentials.userToken
        serverToken = credentials.serverToken
        isApplyingLoadedCredentials = false
        hasLoadedCredentials = true
        isLoadingCredentials = false
        credentialLoadingTask = nil
        credentialLoadingErrorMessage = nil
    }

    private static func credentialErrorMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func recordCredentialPersistenceSuccess(account: String) {
        credentialPersistenceErrors[account] = nil
        updateCredentialPersistenceErrorMessage()
    }

    private func recordCredentialPersistenceFailure(_ error: Error, account: String) {
        credentialPersistenceErrors[account] = error
        updateCredentialPersistenceErrorMessage()
    }

    private func updateCredentialPersistenceErrorMessage() {
        let messages = credentialPersistenceErrors.values
            .map(Self.credentialErrorMessage)
        credentialPersistenceErrorMessage = Array(Set(messages)).sorted().joined(separator: " ").nilIfBlank
    }

    var connectionRecheckIntervalDuration: Duration? {
        guard connectionRecheckIntervalSeconds > 0 else {
            return nil
        }

        return .seconds(connectionRecheckIntervalSeconds)
    }

    var historyPollIntervalDuration: Duration {
        .seconds(historyPollIntervalSeconds)
    }

    func videoQuality(for connectionKind: PlexConnectionKind?) -> PlexVideoQuality {
        PlexVideoQualityPreferences(
            local: localVideoQuality,
            remote: remoteVideoQuality
        ).quality(for: connectionKind)
    }

    func setVideoQuality(_ quality: PlexVideoQuality, for connectionKind: PlexConnectionKind?) {
        if connectionKind == .local {
            localVideoQuality = quality
        } else {
            remoteVideoQuality = quality
        }
    }
}
