import Foundation
import Testing
@testable import PlexBar

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
@Test func rotatesAndPersistsClientIdentifier() async throws {
    let suiteName = "PlexBarTests.rotatesAndPersistsClientIdentifier"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    let initialClientIdentifier = store.clientIdentifier

    let rotatedClientIdentifier = store.rotateClientIdentifier()

    #expect(rotatedClientIdentifier == store.clientIdentifier)
    #expect(rotatedClientIdentifier != initialClientIdentifier)

    let reloadedStore = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )

    #expect(reloadedStore.clientIdentifier == rotatedClientIdentifier)
}

@MainActor
@Test func clearingAuthenticationPreservesClientIdentifier() async throws {
    let suiteName = "PlexBarTests.clearingAuthenticationPreservesClientIdentifier"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )
    let initialClientIdentifier = store.clientIdentifier

    store.saveAuthenticatedUserToken("user-token")
    store.serverToken = "server-token"
    store.selectedServerIdentifier = "server-id"
    store.selectedServerName = "Server"
    store.cachedConnectionURLString = "http://plex.local:32400"
    store.cachedConnectionKind = .local

    store.clearAuthentication()

    #expect(store.clientIdentifier == initialClientIdentifier)
    #expect(store.userToken.isEmpty)
    #expect(store.serverToken.isEmpty)
    #expect(store.selectedServerIdentifier == nil)
    #expect(store.selectedServerName == nil)
    #expect(store.cachedConnectionURLString.isEmpty)
    #expect(store.cachedConnectionKind == nil)
}
