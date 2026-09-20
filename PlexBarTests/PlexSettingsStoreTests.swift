@testable import PlexClientKit
import Foundation
import Testing
@testable import PlexBar

@MainActor
private final class TestLoginItemService: PlexLoginItemControlling {
    var currentStatus: PlexLoginItemStatus
    var setEnabledCalls: [Bool] = []
    var openSystemSettingsCallCount = 0
    var error: Error?

    init(status: PlexLoginItemStatus) {
        currentStatus = status
    }

    func status() -> PlexLoginItemStatus {
        currentStatus
    }

    func setEnabled(_ enabled: Bool) throws {
        setEnabledCalls.append(enabled)

        if let error {
            throw error
        }

        currentStatus = enabled ? .enabled : .notRegistered
    }

    func openSystemSettingsLoginItems() {
        openSystemSettingsCallCount += 1
    }
}

private struct TestLoginItemError: LocalizedError {
    let errorDescription: String?
}

private actor RecordingCredentialStore: PlexCredentialPersisting {
    private var credentials: PlexStoredCredentials
    private var loadCount = 0

    init(credentials: PlexStoredCredentials) {
        self.credentials = credentials
    }

    func loadCredentials() async -> PlexStoredCredentials {
        loadCount += 1
        return credentials
    }

    func replace(_ value: String?, account: String) async {
        switch account {
        case KeychainAccounts.userToken:
            credentials = PlexStoredCredentials(
                userToken: value ?? "",
                serverToken: credentials.serverToken
            )
        case KeychainAccounts.serverToken:
            credentials = PlexStoredCredentials(
                userToken: credentials.userToken,
                serverToken: value ?? ""
            )
        default:
            break
        }
    }

    func recordedLoadCount() -> Int {
        loadCount
    }
}

private struct CredentialStoreTestError: LocalizedError {
    let errorDescription: String? = "Credential storage is unavailable."
}

private actor RecoveringCredentialStore: PlexCredentialPersisting {
    private var credentials: PlexStoredCredentials
    private var loadFailuresRemaining: Int
    private var replaceFailuresRemaining: Int

    init(
        credentials: PlexStoredCredentials,
        loadFailuresRemaining: Int = 0,
        replaceFailuresRemaining: Int = 0
    ) {
        self.credentials = credentials
        self.loadFailuresRemaining = loadFailuresRemaining
        self.replaceFailuresRemaining = replaceFailuresRemaining
    }

    func loadCredentials() throws -> PlexStoredCredentials {
        if loadFailuresRemaining > 0 {
            loadFailuresRemaining -= 1
            throw CredentialStoreTestError()
        }
        return credentials
    }

    func replace(_ value: String?, account: String) throws {
        if replaceFailuresRemaining > 0 {
            replaceFailuresRemaining -= 1
            throw CredentialStoreTestError()
        }

        switch account {
        case KeychainAccounts.userToken:
            credentials = PlexStoredCredentials(
                userToken: value ?? "",
                serverToken: credentials.serverToken
            )
        case KeychainAccounts.serverToken:
            credentials = PlexStoredCredentials(
                userToken: credentials.userToken,
                serverToken: value ?? ""
            )
        default:
            break
        }
    }
}

private actor BlockingCredentialStore: PlexCredentialPersisting {
    private var credentials: PlexStoredCredentials
    private var shouldBlockNextReplacement = true
    private var isReplacementBlocked = false
    private var replacementContinuation: CheckedContinuation<Void, Never>?

    init(credentials: PlexStoredCredentials) {
        self.credentials = credentials
    }

    func loadCredentials() -> PlexStoredCredentials {
        credentials
    }

    func replace(_ value: String?, account: String) async {
        if shouldBlockNextReplacement {
            shouldBlockNextReplacement = false
            isReplacementBlocked = true
            await withCheckedContinuation { continuation in
                replacementContinuation = continuation
            }
            isReplacementBlocked = false
        }

        guard account == KeychainAccounts.userToken else {
            return
        }
        credentials = PlexStoredCredentials(
            userToken: value ?? "",
            serverToken: credentials.serverToken
        )
    }

    func waitUntilReplacementIsBlocked() async {
        while !isReplacementBlocked {
            await Task.yield()
        }
    }

    func resumeReplacement() {
        replacementContinuation?.resume()
        replacementContinuation = nil
    }
}

@MainActor
@Test func defersCredentialAccessUntilAsyncStartup() async throws {
    let suiteName = "PlexBarTests.defersCredentialAccessUntilAsyncStartup"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let credentials = PlexStoredCredentials(userToken: "user-token", serverToken: "server-token")
    let credentialStore = RecordingCredentialStore(credentials: credentials)

    let store = PlexSettingsStore(defaults: defaults, credentialStore: credentialStore)

    let initialLoadCount = await credentialStore.recordedLoadCount()
    #expect(initialLoadCount == 0)
    #expect(!store.hasLoadedCredentials)
    #expect(store.userToken.isEmpty)
    #expect(store.serverToken.isEmpty)

    await store.loadCredentials()

    let finalLoadCount = await credentialStore.recordedLoadCount()
    #expect(finalLoadCount == 1)
    #expect(store.hasLoadedCredentials)
    #expect(store.userToken == "user-token")
    #expect(store.serverToken == "server-token")
}

@MainActor
@Test func credentialLoadFailureIsRetryableAndNeverBecomesAnEmptyAccount() async throws {
    let suiteName = "PlexBarTests.credentialLoadFailureIsRetryableAndNeverBecomesAnEmptyAccount"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let credentialStore = RecoveringCredentialStore(
        credentials: PlexStoredCredentials(userToken: "user-token", serverToken: "server-token"),
        loadFailuresRemaining: 1
    )
    let store = PlexSettingsStore(defaults: defaults, credentialStore: credentialStore)

    await store.loadCredentials()

    #expect(!store.hasLoadedCredentials)
    #expect(!store.isLoadingCredentials)
    #expect(store.userToken.isEmpty)
    #expect(store.serverToken.isEmpty)
    #expect(store.credentialLoadingErrorMessage == "Credential storage is unavailable.")

    await store.loadCredentials()

    #expect(store.hasLoadedCredentials)
    #expect(store.userToken == "user-token")
    #expect(store.serverToken == "server-token")
    #expect(store.credentialLoadingErrorMessage == nil)
}

@MainActor
@Test func failedDurableTokenWriteDoesNotPublishAuthenticationAndCanRecover() async throws {
    let suiteName = "PlexBarTests.failedDurableTokenWriteDoesNotPublishAuthenticationAndCanRecover"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let credentialStore = RecoveringCredentialStore(
        credentials: .empty,
        replaceFailuresRemaining: 1
    )
    let store = PlexSettingsStore(
        defaults: defaults,
        credentialStore: credentialStore,
        initialCredentials: .empty
    )

    await #expect(throws: CredentialStoreTestError.self) {
        try await store.saveAuthenticatedUserToken("new-token")
    }

    #expect(!store.hasAuthenticatedAccount)
    #expect(store.userToken.isEmpty)
    #expect(store.credentialPersistenceErrorMessage == "Credential storage is unavailable.")

    try await store.saveAuthenticatedUserToken("new-token")

    #expect(store.hasAuthenticatedAccount)
    #expect(store.userToken == "new-token")
    #expect(store.credentialPersistenceErrorMessage == nil)
    #expect(try await credentialStore.loadCredentials().userToken == "new-token")
}

@MainActor
@Test func cancellationDuringDurableTokenWriteRestoresThePriorCredential() async throws {
    let suiteName = "PlexBarTests.cancellationDuringDurableTokenWriteRestoresThePriorCredential"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let priorCredentials = PlexStoredCredentials(userToken: "prior-token", serverToken: "server-token")
    let credentialStore = BlockingCredentialStore(credentials: priorCredentials)
    let store = PlexSettingsStore(
        defaults: defaults,
        credentialStore: credentialStore,
        initialCredentials: priorCredentials
    )
    let persistenceTask = Task {
        try await store.saveAuthenticatedUserToken("replacement-token")
    }

    await credentialStore.waitUntilReplacementIsBlocked()
    persistenceTask.cancel()
    await credentialStore.resumeReplacement()

    await #expect(throws: CancellationError.self) {
        try await persistenceTask.value
    }
    #expect(store.userToken == "prior-token")
    #expect(store.hasAuthenticatedAccount)
    #expect(await credentialStore.loadCredentials().userToken == "prior-token")
}

@MainActor
@Test(arguments: [false, true], ["", "new-account-token"])
func supersedingAuthenticationWinsOverAnInFlightCredentialWrite(cancelWrite: Bool, replacement: String) async throws {
    let suiteName = "PlexBarTests.supersedingAuthentication.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let prior = PlexStoredCredentials(userToken: "prior-token", serverToken: "server-token")
    let credentials = BlockingCredentialStore(credentials: prior)
    let store = PlexSettingsStore(defaults: defaults, credentialStore: credentials, initialCredentials: prior)
    let oldWrite = Task { try await store.saveAuthenticatedUserToken("refresh-token") }
    await credentials.waitUntilReplacementIsBlocked()
    if cancelWrite { oldWrite.cancel() }
    store.clearAuthentication()
    let revision = store.accountTokenRevision
    let newWrite = Task { try await store.saveAuthenticatedUserToken(replacement) }
    while store.accountTokenRevision == revision { await Task.yield() }
    await credentials.resumeReplacement()

    await #expect(throws: CancellationError.self) { try await oldWrite.value }
    try await newWrite.value
    try await store.waitForCredentialPersistence()
    #expect(store.userToken == replacement)
    #expect(await credentials.loadCredentials().userToken == replacement)
}

@MainActor
@Test func laterCredentialSuccessDoesNotHideAnEarlierAccountFailure() async throws {
    let suiteName = "PlexBarTests.laterCredentialSuccessDoesNotHideAnEarlierAccountFailure"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let initialCredentials = PlexStoredCredentials(
        userToken: "user-token",
        serverToken: "server-token"
    )
    let credentialStore = RecoveringCredentialStore(
        credentials: initialCredentials,
        replaceFailuresRemaining: 1
    )
    let store = PlexSettingsStore(
        defaults: defaults,
        credentialStore: credentialStore,
        initialCredentials: initialCredentials
    )

    store.clearAuthentication()

    await #expect(throws: CredentialStoreTestError.self) {
        try await store.waitForCredentialPersistence()
    }
    #expect(store.credentialPersistenceErrorMessage == "Credential storage is unavailable.")

    try await store.saveAuthenticatedUserToken("")

    #expect(store.credentialPersistenceErrorMessage == nil)
}

@MainActor
@Test func persistsCredentialChangesThroughTheBackgroundStore() async throws {
    let suiteName = "PlexBarTests.persistsCredentialChangesThroughTheBackgroundStore"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let credentialStore = RecordingCredentialStore(credentials: .empty)
    let store = PlexSettingsStore(defaults: defaults, credentialStore: credentialStore)
    await store.loadCredentials()

    try await store.saveAuthenticatedUserToken(" user-token ")
    store.serverToken = "server-token"
    try await store.waitForCredentialPersistence()

    let persistedCredentials = await credentialStore.loadCredentials()
    #expect(persistedCredentials == PlexStoredCredentials(
        userToken: "user-token",
        serverToken: "server-token"
    ))
}

@MainActor
@Test func preservesTheFinalCredentialValueAcrossRapidUpdates() async throws {
    let suiteName = "PlexBarTests.preservesTheFinalCredentialValueAcrossRapidUpdates"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let credentialStore = RecordingCredentialStore(credentials: .empty)
    let store = PlexSettingsStore(defaults: defaults, credentialStore: credentialStore)
    await store.loadCredentials()

    for index in 0..<64 {
        try await store.saveAuthenticatedUserToken("token-\(index)")
    }
    try await store.saveAuthenticatedUserToken("final-token")
    try await store.waitForCredentialPersistence()

    let persistedCredentials = await credentialStore.loadCredentials()
    #expect(persistedCredentials.userToken == "final-token")
}

@MainActor
@Test func defaultsHistoryPollInterval() async throws {
    let suiteName = "PlexBarTests.defaultsHistoryPollInterval"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )

    #expect(store.connectionRecheckIntervalSeconds == AppConstants.defaultConnectionRecheckIntervalSeconds)
    #expect(store.historyPollIntervalSeconds == AppConstants.defaultHistoryPollIntervalSeconds)
}

@MainActor
@Test func persistsConfiguredConnectionRecheckInterval() async throws {
    let suiteName = "PlexBarTests.persistsConfiguredConnectionRecheckInterval"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )

    store.connectionRecheckIntervalSeconds = 1_800

    #expect(store.connectionRecheckIntervalSeconds == 1_800)

    let reloadedStore = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )

    #expect(reloadedStore.connectionRecheckIntervalSeconds == 1_800)
}

@MainActor
@Test func persistsConfiguredHistoryPollInterval() async throws {
    let suiteName = "PlexBarTests.persistsConfiguredHistoryPollInterval"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )

    store.historyPollIntervalSeconds = 3_600

    #expect(store.historyPollIntervalSeconds == 3_600)

    let reloadedStore = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )

    #expect(reloadedStore.historyPollIntervalSeconds == 3_600)
}

@MainActor
@Test func persistsLocalAndRemoteVideoQualityIndependently() async throws {
    let suiteName = "PlexBarTests.persistsLocalAndRemoteVideoQualityIndependently"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(store.localVideoQuality == .original)
    #expect(store.remoteVideoQuality == .original)

    store.localVideoQuality = .fourK20Mbps
    store.remoteVideoQuality = .hd4Mbps

    let reloadedStore = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(reloadedStore.videoQuality(for: .local) == .fourK20Mbps)
    #expect(reloadedStore.videoQuality(for: .remote) == .hd4Mbps)
    #expect(reloadedStore.videoQuality(for: .relay) == .hd4Mbps)
}

@MainActor
@Test func downloadPreferencesPersistIndependentlyFromStreamingQuality() async throws {
    let suiteName = "PlexBarTests.downloadPreferencesPersistIndependentlyFromStreamingQuality"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(store.downloadPreferences == .default)

    store.localVideoQuality = .fourK20Mbps
    store.remoteVideoQuality = .sd1500Kbps
    store.downloadVideoQuality = .fullHD8Mbps
    store.downloadMusicQuality = .kbps256
    store.downloadSubtitlePreference = .selectable

    let reloadedStore = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(reloadedStore.localVideoQuality == .fourK20Mbps)
    #expect(reloadedStore.remoteVideoQuality == .sd1500Kbps)
    #expect(reloadedStore.downloadPreferences == PlexDownloadPreferences(
        videoQuality: .fullHD8Mbps,
        musicQuality: .kbps256,
        subtitlePreference: .selectable
    ))

    defaults.set("unsupported", forKey: "plex.downloadVideoQuality")
    defaults.set("unsupported", forKey: "plex.downloadMusicQuality")
    defaults.set("unsupported", forKey: "plex.downloadSubtitlePreference")
    let normalizedStore = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(normalizedStore.downloadPreferences == .default)
}

@MainActor
@Test func qualitySuggestionsDefaultToEnabledAndPersist() async throws {
    let suiteName = "PlexBarTests.qualitySuggestionsDefaultToEnabledAndPersist"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(store.qualitySuggestionsEnabled)

    store.qualitySuggestionsEnabled = false

    let reloadedStore = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(!reloadedStore.qualitySuggestionsEnabled)
}

@MainActor
@Test func directPlaybackPoliciesDefaultToEnabledAndPersist() async throws {
    let suiteName = "PlexBarTests.directPlaybackPoliciesDefaultToEnabledAndPersist"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(store.allowsDirectPlay)
    #expect(store.allowsDirectStream)
    #expect(!store.forceDirectPlay)
    #expect(store.playbackStreamingPolicy == .automatic)

    store.allowsDirectPlay = false
    store.allowsDirectStream = false
    store.forceDirectPlay = true

    let reloadedStore = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(!reloadedStore.allowsDirectPlay)
    #expect(!reloadedStore.allowsDirectStream)
    #expect(reloadedStore.forceDirectPlay)
    #expect(reloadedStore.playbackStreamingPolicy == PlexPlaybackStreamingPolicy(
        allowsDirectPlay: false,
        allowsDirectStream: false,
        forceDirectPlay: true
    ))
}

@MainActor
@Test func cinemaPreplayDefaultsOffPersistsAndNormalizesUnknownValues() async throws {
    let suiteName = "PlexBarTests.cinemaPreplayDefaultsOffPersistsAndNormalizesUnknownValues"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(store.cinemaPreplayPreference == .off)

    store.cinemaPreplayPreference = .preRollOnly
    let preRollStore = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(preRollStore.cinemaPreplayPreference == .preRollOnly)
    #expect(preRollStore.cinemaPreplayPreference.extrasPrefixCount == 0)

    preRollStore.cinemaPreplayPreference = .fiveTrailers
    let trailerStore = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(trailerStore.cinemaPreplayPreference == .fiveTrailers)
    #expect(trailerStore.cinemaPreplayPreference.extrasPrefixCount == 5)

    defaults.set(99, forKey: "plex.cinemaPreplayPreference")
    let normalizedStore = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(normalizedStore.cinemaPreplayPreference == .off)
    #expect(normalizedStore.cinemaPreplayPreference.extrasPrefixCount == nil)
}

@MainActor
@Test func persistsVideoDynamicRangeAndDefaultsUnknownValuesToAutomatic() async throws {
    let suiteName = "PlexBarTests.persistsVideoDynamicRangeAndDefaultsUnknownValuesToAutomatic"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(store.videoDynamicRange == .automatic)

    store.videoDynamicRange = .constrainedHigh

    let reloadedStore = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(reloadedStore.videoDynamicRange == .constrainedHigh)

    defaults.set("unsupported", forKey: "plex.videoDynamicRange")
    let normalizedStore = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(normalizedStore.videoDynamicRange == .automatic)
}

@MainActor
@Test func persistsVideoScalingAndDefaultsUnknownValuesToFit() async throws {
    let suiteName = "PlexBarTests.persistsVideoScalingAndDefaultsUnknownValuesToFit"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(store.videoScalingMode == .fit)

    store.videoScalingMode = .fill

    let reloadedStore = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(reloadedStore.videoScalingMode == .fill)

    defaults.set("unsupported", forKey: "plex.videoScalingMode")
    let normalizedStore = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(normalizedStore.videoScalingMode == .fit)
}

@MainActor
@Test func persistsEpisodeSpoilerPolicyAndDefaultsUnknownValuesToOff() async throws {
    let suiteName = "PlexBarTests.persistsEpisodeSpoilerPolicyAndDefaultsUnknownValuesToOff"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(store.episodeSpoilerPolicy == .off)

    store.episodeSpoilerPolicy = .unwatchedEpisodes

    let reloadedStore = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(reloadedStore.episodeSpoilerPolicy == .unwatchedEpisodes)

    defaults.set("unsupported", forKey: "plex.episodeSpoilerPolicy")
    let normalizedStore = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(normalizedStore.episodeSpoilerPolicy == .off)
}

@MainActor
@Test func persistsAutoplayPreferencesAndNormalizesUnknownValues() async throws {
    let suiteName = "PlexBarTests.persistsAutoplayPreferencesAndNormalizesUnknownValues"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(store.autoplayUpNext)
    #expect(store.autoplayCountdown == .tenSeconds)
    #expect(store.passoutProtection == .twoHours)
    #expect(store.rewindOnResume == .none)

    store.autoplayUpNext = false
    store.autoplayCountdown = .thirtySeconds
    store.passoutProtection = .threeHours
    store.rewindOnResume = PlexRewindOnResume(seconds: 17)

    let reloadedStore = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(!reloadedStore.autoplayUpNext)
    #expect(reloadedStore.autoplayCountdown == .thirtySeconds)
    #expect(reloadedStore.passoutProtection == .threeHours)
    #expect(reloadedStore.rewindOnResume == PlexRewindOnResume(seconds: 17))

    defaults.set(11, forKey: "plex.autoplayCountdown")
    defaults.set(101, forKey: "plex.passoutProtection")
    defaults.set(45, forKey: "plex.rewindOnResumeSeconds")
    let normalizedStore = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(normalizedStore.autoplayCountdown == .tenSeconds)
    #expect(normalizedStore.passoutProtection == .twoHours)
    #expect(normalizedStore.rewindOnResume == PlexRewindOnResume(seconds: 30))
}

@MainActor
@Test func persistsPlaybackMarkerPreferencesAndDefaultsUnknownValuesToManual() async throws {
    let suiteName = "PlexBarTests.persistsPlaybackMarkerPreferencesAndDefaultsUnknownValuesToManual"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(store.skipIntroBehavior == .manually)
    #expect(store.skipAdsBehavior == .manually)
    #expect(store.skipCreditsBehavior == .manually)

    store.skipIntroBehavior = .automatically
    store.skipAdsBehavior = .disabled
    store.skipCreditsBehavior = .automatically

    let reloadedStore = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(reloadedStore.playbackMarkerPreferences == PlexPlaybackMarkerPreferences(
        intro: .automatically,
        ads: .disabled,
        credits: .automatically
    ))

    defaults.set("unsupported", forKey: "plex.skipIntroBehavior")
    defaults.set("unsupported", forKey: "plex.skipAdsBehavior")
    defaults.set("unsupported", forKey: "plex.skipCreditsBehavior")
    let normalizedStore = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(normalizedStore.skipIntroBehavior == .manually)
    #expect(normalizedStore.skipAdsBehavior == .manually)
    #expect(normalizedStore.skipCreditsBehavior == .manually)
}

@MainActor
@Test func reusesPersistedClientIdentifier() async throws {
    let suiteName = "PlexBarTests.reusesPersistedClientIdentifier"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    defaults.set("existing-client-id", forKey: "plex.clientIdentifier")

    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )

    #expect(store.clientIdentifier == "existing-client-id")
}

@MainActor
@Test func persistsRegisteredJWTKeyIdentity() async throws {
    let suiteName = "PlexBarTests.persistsRegisteredJWTKeyIdentity"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    #expect(store.registeredJWTKeyID == nil)

    store.markJWTKeyRegistered(keyID: "device-key")

    let reloadedStore = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )

    #expect(reloadedStore.registeredJWTKeyID == "device-key")
}

@MainActor
@Test func clearingAuthenticationPreservesDeviceIdentityState() async throws {
    let suiteName = "PlexBarTests.clearingAuthenticationPreservesDeviceIdentityState"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let credentialStore = RecordingCredentialStore(credentials: .empty)
    let store = PlexSettingsStore(
        defaults: defaults,
        credentialStore: credentialStore
    )
    let initialClientIdentifier = store.clientIdentifier
    store.markJWTKeyRegistered(keyID: "device-key")

    try await store.saveAuthenticatedUserToken("user-token")
    store.serverToken = "server-token"
    store.selectedServerIdentifier = "server-id"
    store.selectedServerName = "Server"
    store.cachedConnectionURLString = "http://plex.local:32400"
    store.cachedConnectionKind = .local

    store.clearAuthentication()
    try await store.waitForCredentialPersistence()

    #expect(store.clientIdentifier == initialClientIdentifier)
    #expect(store.registeredJWTKeyID == "device-key")
    #expect(store.userToken.isEmpty)
    #expect(store.serverToken.isEmpty)
    #expect(store.selectedServerIdentifier == nil)
    #expect(store.selectedServerName == nil)
    #expect(store.cachedConnectionURLString.isEmpty)
    #expect(store.cachedConnectionKind == nil)

    let persistedCredentials = await credentialStore.loadCredentials()
    #expect(persistedCredentials == .empty)
}

@MainActor
@Test func loadsOpenAtLoginStatusFromService() async throws {
    let suiteName = "PlexBarTests.loadsOpenAtLoginStatusFromService"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let loginItemService = TestLoginItemService(status: .requiresApproval)
    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)"),
        loginItemService: loginItemService
    )

    #expect(store.openAtLoginStatus == .requiresApproval)
    #expect(store.opensAtLogin)
    #expect(store.openAtLoginRequiresApproval)
}

@MainActor
@Test func enablesOpenAtLoginThroughService() async throws {
    let suiteName = "PlexBarTests.enablesOpenAtLoginThroughService"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let loginItemService = TestLoginItemService(status: .notRegistered)
    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)"),
        loginItemService: loginItemService
    )

    store.setOpenAtLogin(true)

    #expect(loginItemService.setEnabledCalls == [true])
    #expect(store.openAtLoginStatus == .enabled)
    #expect(store.opensAtLogin)
    #expect(store.openAtLoginErrorMessage == nil)
}

@MainActor
@Test func recordsOpenAtLoginToggleFailure() async throws {
    let suiteName = "PlexBarTests.recordsOpenAtLoginToggleFailure"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let loginItemService = TestLoginItemService(status: .notRegistered)
    loginItemService.error = TestLoginItemError(errorDescription: "Launch denied by user.")

    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)"),
        loginItemService: loginItemService
    )

    store.setOpenAtLogin(true)

    #expect(loginItemService.setEnabledCalls == [true])
    #expect(store.openAtLoginStatus == .notRegistered)
    #expect(store.openAtLoginErrorMessage == "PlexBar could not enable Open at Login. Launch denied by user.")
}

@MainActor
@Test func opensLoginItemsSystemSettingsThroughService() async throws {
    let suiteName = "PlexBarTests.opensLoginItemsSystemSettingsThroughService"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let loginItemService = TestLoginItemService(status: .requiresApproval)
    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)"),
        loginItemService: loginItemService
    )

    store.openLoginItemsSystemSettings()

    #expect(loginItemService.openSystemSettingsCallCount == 1)
}

@MainActor
@Test func refreshingOpenAtLoginStatusClearsStaleErrorMessage() async throws {
    let suiteName = "PlexBarTests.refreshingOpenAtLoginStatusClearsStaleErrorMessage"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let loginItemService = TestLoginItemService(status: .notRegistered)
    loginItemService.error = TestLoginItemError(errorDescription: "Launch denied by user.")

    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)"),
        loginItemService: loginItemService
    )

    store.setOpenAtLogin(true)
    #expect(store.openAtLoginErrorMessage == "PlexBar could not enable Open at Login. Launch denied by user.")

    loginItemService.error = nil
    loginItemService.currentStatus = .enabled

    store.refreshOpenAtLoginStatus()

    #expect(store.openAtLoginStatus == .enabled)
    #expect(store.openAtLoginErrorMessage == nil)
}
