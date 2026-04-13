import Foundation
import Testing
@testable import PlexBar

@MainActor
@Test func defaultsPollIntervalToFifteenSeconds() async throws {
    let suiteName = "PlexBarTests.defaultsPollIntervalToFifteenSeconds"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )

    #expect(store.pollIntervalSeconds == AppConstants.defaultPollIntervalSeconds)
    #expect(store.historyPollIntervalSeconds == AppConstants.defaultHistoryPollIntervalSeconds)
}

@MainActor
@Test func clampsAndPersistsConfiguredPollInterval() async throws {
    let suiteName = "PlexBarTests.clampsAndPersistsConfiguredPollInterval"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )

    store.pollIntervalSeconds = 999

    #expect(store.pollIntervalSeconds == AppConstants.maximumPollIntervalSeconds)

    let reloadedStore = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(suiteName)")
    )

    #expect(reloadedStore.pollIntervalSeconds == AppConstants.maximumPollIntervalSeconds)
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
    store.serverURLString = "http://plex.local:32400"

    store.clearAuthentication()

    #expect(store.clientIdentifier == initialClientIdentifier)
    #expect(store.userToken.isEmpty)
    #expect(store.serverToken.isEmpty)
    #expect(store.selectedServerIdentifier == nil)
    #expect(store.selectedServerName == nil)
    #expect(store.serverURLString.isEmpty)
}
