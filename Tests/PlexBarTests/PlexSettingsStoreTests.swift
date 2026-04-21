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
