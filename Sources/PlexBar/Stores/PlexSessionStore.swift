import Foundation
import Observation

@MainActor
@Observable
final class PlexSessionStore {
    typealias ConnectionRecheckSleep = @Sendable (Duration) async throws -> Void

    private enum GeoLookupState {
        case inFlight
        case resolved(String)
        case unavailable
    }

    private enum GeoLookupOutcome {
        case resolved(String)
        case unavailable
        case retryableFailure
        case cancelled
    }

    private let connectionStore: PlexConnectionStore
    private let client: PlexAPIClient
    private let geoIPClient: PlexGeoIPClient
    private let eventsClient: PlexSessionEventsClient
    private let connectionRecheckSleep: ConnectionRecheckSleep
    private var monitorTask: Task<Void, Never>?
    private var connectionRecheckTask: Task<Void, Never>?
    private var geoLookupTasksByIP: [String: Task<Void, Never>] = [:]
    private var geoLookupStateByIP: [String: GeoLookupState] = [:]
    private var resolvedLocationsBySessionKey: [String: String] = [:]
    private var sessionsByKey: [String: PlexSession] = [:]
    private var sessionOrder: [String] = []
    private var activeServerIdentifier: String?
    private var activeMonitorURL: URL?

    var sessions: [PlexSession] {
        sessionOrder.compactMap { sessionsByKey[$0] }
    }

    var isLoading = false
    var errorMessage: String?
    var lastUpdated: Date?

    init(
        connectionStore: PlexConnectionStore,
        client: PlexAPIClient = PlexAPIClient(),
        geoIPClient: PlexGeoIPClient = PlexGeoIPClient(),
        eventsClient: PlexSessionEventsClient = PlexSessionEventsClient(),
        connectionRecheckSleep: @escaping ConnectionRecheckSleep = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.connectionStore = connectionStore
        self.client = client
        self.geoIPClient = geoIPClient
        self.eventsClient = eventsClient
        self.connectionRecheckSleep = connectionRecheckSleep
    }

    var activeStreamCount: Int {
        sessionsByKey.count
    }

    func refreshNow() {
        Task {
            await performFullHydrate()
        }
    }

    func resolvedLocation(for session: PlexSession) -> String? {
        guard let sessionKey = session.canonicalSessionKey else {
            return nil
        }

        return resolvedLocationsBySessionKey[sessionKey]
    }

    func didChangeConfiguration() {
        cancelBackgroundTasks()
        clearGeoLookups()

        guard connectionStore.settings.hasValidConfiguration else {
            activeServerIdentifier = nil
            activeMonitorURL = nil
            clearSessions(resetTimestamp: true)
            errorMessage = nil
            isLoading = false
            return
        }

        activeServerIdentifier = connectionStore.settings.selectedServerIdentifier
        startMonitorTask()
        startConnectionRecheckTask()
    }

    func restartConnectionRecheckTask() {
        connectionRecheckTask?.cancel()
        connectionRecheckTask = nil

        guard connectionStore.settings.hasValidConfiguration else {
            return
        }

        startConnectionRecheckTask()
    }

    private func runMonitorLoop() async {
        var reconnectAttempt = 0
        var forceRefresh = true

        while !Task.isCancelled {
            guard connectionStore.settings.hasValidConfiguration else {
                clearSessions(resetTimestamp: true)
                errorMessage = nil
                isLoading = false
                return
            }

            do {
                let configuration = try await connectionStore.currentConfiguration(forceRefresh: forceRefresh)
                activeMonitorURL = configuration.serverURL

                try await eventsClient.monitor(using: configuration) { [weak self] event in
                    guard let self else {
                        throw CancellationError()
                    }

                    try await self.handle(event, using: configuration)
                }

                reconnectAttempt = 0
                forceRefresh = true
            } catch is CancellationError {
                activeMonitorURL = nil
                return
            } catch {
                activeMonitorURL = nil
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                reconnectAttempt += 1
                forceRefresh = true

                do {
                    try await Task.sleep(for: reconnectBackoff(after: reconnectAttempt))
                } catch {
                    return
                }
            }
        }
    }

    private func runConnectionRecheckLoop() async {
        while !Task.isCancelled {
            guard let recheckDuration = connectionStore.settings.connectionRecheckIntervalDuration else {
                return
            }

            do {
                try await connectionRecheckSleep(recheckDuration)
            } catch is CancellationError {
                return
            } catch {
                return
            }

            guard !Task.isCancelled,
                  connectionStore.settings.hasValidConfiguration,
                  connectionStore.activeConnectionKind != .local,
                  let currentMonitorURL = activeMonitorURL else {
                continue
            }

            do {
                let refreshedConfiguration = try await connectionStore.currentConfiguration(forceRefresh: true)

                guard refreshedConfiguration.serverURL != currentMonitorURL else {
                    continue
                }

                startMonitorTask()
            } catch is CancellationError {
                return
            } catch {
                continue
            }
        }
    }

    private func handle(
        _ event: PlexSessionEvent,
        using configuration: PlexConnectionConfiguration
    ) async throws {
        switch event {
        case .connected:
            try await hydrateAll(using: configuration, showLoading: true)
        case .playing(let notification):
            try await handlePlayingNotification(notification, using: configuration)
        case .transcodeSessionUpdate:
            return
        }
    }

    private func handlePlayingNotification(
        _ notification: PlexPlaySessionStateNotification,
        using configuration: PlexConnectionConfiguration
    ) async throws {
        guard let sessionKey = notification.sessionKey?.nilIfBlank else {
            return
        }

        if notification.state?.lowercased() == "stopped" {
            removeSession(for: sessionKey)
            return
        }

        guard let existingSession = sessionsByKey[sessionKey] else {
            try await rehydrateSession(using: configuration, sessionKey: sessionKey)
            return
        }

        if notification.requiresHydrate(comparedTo: existingSession) {
            try await rehydrateSession(using: configuration, sessionKey: sessionKey)
            return
        }

        sessionsByKey[sessionKey] = existingSession.applying(playNotification: notification)
        refreshResolvedLocationsIfNeeded()
        errorMessage = nil
        lastUpdated = Date()
    }

    private func rehydrateSession(
        using configuration: PlexConnectionConfiguration,
        sessionKey: String
    ) async throws {
        if let session = try await client.fetchSession(using: configuration, sessionKey: sessionKey),
           let canonicalSessionKey = session.canonicalSessionKey {
            upsertSession(session, sessionKey: canonicalSessionKey)
        } else {
            removeSession(for: sessionKey)
        }

        errorMessage = nil
        lastUpdated = Date()
    }

    private func performFullHydrate() async {
        guard connectionStore.settings.hasValidConfiguration else {
            clearSessions(resetTimestamp: true)
            errorMessage = nil
            isLoading = false
            return
        }

        if monitorTask == nil || activeServerIdentifier != connectionStore.settings.selectedServerIdentifier {
            didChangeConfiguration()
        }

        isLoading = true

        do {
            try await connectionStore.perform { configuration in
                try await hydrateAll(using: configuration, showLoading: false)
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isLoading = false
    }

    private func hydrateAll(
        using configuration: PlexConnectionConfiguration,
        showLoading: Bool
    ) async throws {
        if showLoading {
            isLoading = true
        }
        defer {
            if showLoading {
                isLoading = false
            }
        }

        let fetchedSessions = try await client.fetchSessions(using: configuration)
        applyHydratedSessions(fetchedSessions)
    }

    private func applyHydratedSessions(_ fetchedSessions: [PlexSession]) {
        var nextSessionsByKey: [String: PlexSession] = [:]
        var nextSessionOrder: [String] = []

        for session in fetchedSessions {
            guard let storageKey = session.canonicalSessionKey else {
                continue
            }

            guard nextSessionsByKey[storageKey] == nil else {
                continue
            }

            nextSessionsByKey[storageKey] = session
            nextSessionOrder.append(storageKey)
        }

        sessionsByKey = nextSessionsByKey
        sessionOrder = nextSessionOrder
        refreshResolvedLocationsIfNeeded()
        errorMessage = nil
        lastUpdated = Date()
    }

    private func upsertSession(_ session: PlexSession, sessionKey: String) {
        sessionsByKey[sessionKey] = session

        if !sessionOrder.contains(sessionKey) {
            sessionOrder.append(sessionKey)
        }

        refreshResolvedLocationsIfNeeded()
    }

    private func removeSession(for sessionKey: String) {
        sessionsByKey.removeValue(forKey: sessionKey)
        sessionOrder.removeAll { $0 == sessionKey }
        refreshResolvedLocationsIfNeeded()
        errorMessage = nil
        lastUpdated = Date()
    }

    private func clearSessions(resetTimestamp: Bool) {
        sessionsByKey = [:]
        sessionOrder = []
        refreshResolvedLocationsIfNeeded()

        if resetTimestamp {
            lastUpdated = nil
        }
    }

    private func reconnectBackoff(after attempt: Int) -> Duration {
        let seconds = min(max(1 << min(attempt, 4), 1), 30)
        return .seconds(seconds)
    }

    private func cancelBackgroundTasks() {
        monitorTask?.cancel()
        monitorTask = nil
        connectionRecheckTask?.cancel()
        connectionRecheckTask = nil
        geoLookupTasksByIP.values.forEach { $0.cancel() }
        geoLookupTasksByIP.removeAll()
    }

    private func startMonitorTask() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            await self?.runMonitorLoop()
        }
    }

    private func startConnectionRecheckTask() {
        guard connectionStore.settings.connectionRecheckIntervalDuration != nil else {
            return
        }

        connectionRecheckTask = Task { [weak self] in
            await self?.runConnectionRecheckLoop()
        }
    }

    private func refreshResolvedLocationsIfNeeded() {
        resolvedLocationsBySessionKey = sessionOrder.reduce(into: [:]) { partialResult, sessionKey in
            guard let session = sessionsByKey[sessionKey],
                  let ipAddress = session.geoLookupIPAddress,
                  case .resolved(let location) = geoLookupStateByIP[ipAddress] else {
                return
            }

            partialResult[sessionKey] = location
        }

        guard connectionStore.settings.hasAuthenticatedAccount else {
            return
        }

        for sessionKey in sessionOrder {
            guard let session = sessionsByKey[sessionKey],
                  let ipAddress = session.geoLookupIPAddress,
                  geoLookupStateByIP[ipAddress] == nil else {
                continue
            }

            startGeoLookup(for: ipAddress)
        }
    }

    private func startGeoLookup(for ipAddress: String) {
        guard geoLookupTasksByIP[ipAddress] == nil else {
            return
        }

        let userToken = connectionStore.settings.trimmedUserToken
        guard !userToken.isEmpty else {
            return
        }

        let clientContext = PlexClientContext(clientIdentifier: connectionStore.settings.clientIdentifier)
        let geoIPClient = self.geoIPClient
        geoLookupStateByIP[ipAddress] = .inFlight

        geoLookupTasksByIP[ipAddress] = Task { [weak self] in
            do {
                let resolvedLocation = try await geoIPClient.fetchGeoLocation(
                    ipAddress: ipAddress,
                    userToken: userToken,
                    clientContext: clientContext
                )?.displayName
                let outcome: GeoLookupOutcome
                if let resolvedLocation = resolvedLocation?.nilIfBlank {
                    outcome = .resolved(resolvedLocation)
                } else {
                    outcome = .unavailable
                }

                await MainActor.run {
                    self?.finishGeoLookup(for: ipAddress, outcome: outcome)
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.finishGeoLookup(for: ipAddress, outcome: .cancelled)
                }
            } catch let error as URLError where error.code == .cancelled {
                await MainActor.run {
                    self?.finishGeoLookup(for: ipAddress, outcome: .cancelled)
                }
            } catch {
                await MainActor.run {
                    self?.finishGeoLookup(for: ipAddress, outcome: .retryableFailure)
                }
            }
        }
    }

    @MainActor
    private func finishGeoLookup(for ipAddress: String, outcome: GeoLookupOutcome) {
        geoLookupTasksByIP.removeValue(forKey: ipAddress)

        switch outcome {
        case .resolved(let resolvedLocation):
            geoLookupStateByIP[ipAddress] = .resolved(resolvedLocation)
            refreshResolvedLocationsIfNeeded()
        case .unavailable:
            geoLookupStateByIP[ipAddress] = .unavailable
            refreshResolvedLocationsIfNeeded()
        case .retryableFailure, .cancelled:
            geoLookupStateByIP.removeValue(forKey: ipAddress)
        }
    }

    private func clearGeoLookups() {
        geoLookupTasksByIP.values.forEach { $0.cancel() }
        geoLookupTasksByIP.removeAll()
        geoLookupStateByIP.removeAll()
        resolvedLocationsBySessionKey.removeAll()
    }
}

private extension PlexPlaySessionStateNotification {
    func requiresHydrate(comparedTo session: PlexSession) -> Bool {
        if hasRatingKey, ratingKey != session.ratingKey {
            return true
        }

        if hasKey, key != session.key {
            return true
        }

        if hasTranscodeSession, transcodeSessionKey != session.transcodeSessionKey {
            return true
        }

        return false
    }
}
