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
    private let activityClock: PlexActivityRefreshClock
    private static let activityRefreshInterval: Duration = .seconds(10)
    private var activityConsumers: Set<UUID> = []
    private var activityRefreshTask: Task<Void, Never>?
    private var activityRefreshID = UUID()
    private var lastHydratedInstant: ContinuousClock.Instant?
    private var isSystemAsleep = false
    private var hydration: (id: UUID, scope: String, url: URL, task: Task<Void, Error>)?
    private var hydrationNotifications: [PlexPlaySessionStateNotification] = []
    private var hydrationNeedsFollowup = false
    private var monitorTask: Task<Void, Never>?
    private var connectionRecheckTask: Task<Void, Never>?
    private var geoLookupTasksByIP: [String: Task<Void, Never>] = [:]
    private var geoLookupStateByIP: [String: GeoLookupState] = [:]
    private var resolvedLocationsBySessionKey: [String: String] = [:]
    private var sessionsByKey: [String: PlexSession] = [:]
    private var sessionOrder: [String] = []
    private var terminatingSessionKeys: Set<String> = []
    private var waveformLevelsByStreamID: [Int: [Double]] = [:]
    private var waveformUnavailableStreamIDs: Set<Int> = []
    private var waveformLevelTasksByStreamID: [Int: Task<Void, Never>] = [:]
    private var activeServerIdentifier: String?
    private var activeAccountScope: String?
    private var activeMonitorURL: URL?

    var sessions: [PlexSession] {
        sessionOrder.compactMap { sessionsByKey[$0] }
    }

    var isLoading = false
    var errorMessage: String?
    var lastUpdated: Date?
    private(set) var lastHydratedAt: Date?
    private(set) var activityErrorMessage: String?

    var activitySummary: PlexActivitySummary {
        PlexActivitySummary(sessions: sessions)
    }

    init(
        connectionStore: PlexConnectionStore,
        client: PlexAPIClient = PlexAPIClient(),
        geoIPClient: PlexGeoIPClient = PlexGeoIPClient(),
        eventsClient: PlexSessionEventsClient = PlexSessionEventsClient(),
        connectionRecheckSleep: @escaping ConnectionRecheckSleep = { duration in
            try await Task.sleep(for: duration)
        },
        activityClock: PlexActivityRefreshClock = .continuous
    ) {
        self.connectionStore = connectionStore
        self.client = client
        self.geoIPClient = geoIPClient
        self.eventsClient = eventsClient
        self.connectionRecheckSleep = connectionRecheckSleep
        self.activityClock = activityClock
    }

    var activeStreamCount: Int {
        sessionOrder.count
    }

    func isTerminating(_ session: PlexSession) -> Bool {
        guard let sessionKey = session.canonicalSessionKey else {
            return false
        }

        return terminatingSessionKeys.contains(sessionKey)
    }

    @discardableResult
    func refreshNow() -> Task<Void, Never> {
        Task {
            await performFullHydrate()
        }
    }

    func setActivityVisible(_ isVisible: Bool, consumer: UUID) {
        let wasVisible = !activityConsumers.isEmpty
        if isVisible {
            activityConsumers.insert(consumer)
        } else {
            activityConsumers.remove(consumer)
        }
        if activityConsumers.isEmpty {
            cancelActivityRefresh()
        } else if !wasVisible {
            let deadline = lastHydratedInstant.map { $0 + Self.activityRefreshInterval } ?? activityClock.now()
            scheduleActivityRefresh(at: max(deadline, activityClock.now()))
        }
    }

    func systemWillSleep() {
        isSystemAsleep = true
        cancelActivityRefresh()
        cancelHydration()
        monitorTask?.cancel()
        monitorTask = nil
        connectionRecheckTask?.cancel()
        connectionRecheckTask = nil
    }

    func systemDidWake() {
        isSystemAsleep = false
        guard connectionStore.settings.hasValidConfiguration else { return }
        startMonitorTask()
        restartConnectionRecheckTask()
        scheduleActivityRefresh(at: activityClock.now())
    }

    func terminate(_ session: PlexSession, reason: String? = nil) async {
        guard let sessionKey = session.canonicalSessionKey else {
            errorMessage = PlexSessionStoreError.missingSessionKey.errorDescription
            return
        }

        guard !terminatingSessionKeys.contains(sessionKey) else {
            return
        }

        terminatingSessionKeys.insert(sessionKey)
        defer {
            terminatingSessionKeys.remove(sessionKey)
        }

        do {
            guard let serverSessionID = session.serverSessionID else {
                throw PlexSessionStoreError.missingServerSessionID
            }

            let configuration = try await connectionStore.currentConfiguration(forceRefresh: true)
            try await client.terminateSession(
                using: configuration,
                sessionID: serverSessionID,
                reason: reason
            )

            do {
                try await connectionStore.perform { configuration in
                    try await hydrateAll(using: configuration, showLoading: false, afterPlaybackChange: true)
                }
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func resolvedLocation(for session: PlexSession) -> String? {
        guard let sessionKey = session.canonicalSessionKey else {
            return nil
        }

        return resolvedLocationsBySessionKey[sessionKey]
    }

    func waveformLevels(for session: PlexSession) -> [Double]? {
        guard let streamID = session.audioStreamID else {
            return nil
        }

        return waveformLevelsByStreamID[streamID]
    }

    func loadWaveformLevelsIfNeeded(for session: PlexSession, subsample: Int = 96) {
        guard session.contentKind == .track,
              let streamID = session.audioStreamID,
              waveformLevelsByStreamID[streamID] == nil,
              waveformUnavailableStreamIDs.contains(streamID) == false,
              waveformLevelTasksByStreamID[streamID] == nil else {
            return
        }

        let client = self.client
        waveformLevelTasksByStreamID[streamID] = Task { [weak self] in
            do {
                guard let self else {
                    return
                }

                let configuration = try await connectionStore.currentConfiguration()
                let levels = try await client.fetchStreamLevels(
                    using: configuration,
                    streamID: streamID,
                    subsample: subsample
                )

                await MainActor.run {
                    self.finishWaveformLoad(streamID: streamID, levels: levels)
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.finishCancelledWaveformLoad(streamID: streamID)
                }
            } catch let error as URLError where error.code == .cancelled {
                await MainActor.run {
                    self?.finishCancelledWaveformLoad(streamID: streamID)
                }
            } catch {
                await MainActor.run {
                    self?.finishWaveformLoad(streamID: streamID, levels: nil)
                }
            }
        }
    }

    func didChangeConfiguration() {
        cancelBackgroundTasks()
        clearGeoLookups()
        clearWaveformCache()

        if activeAccountScope != connectionStore.accountCacheScope {
            clearSessions(resetTimestamp: true)
            errorMessage = nil
        }

        guard connectionStore.settings.hasValidConfiguration else {
            activeServerIdentifier = nil
            activeMonitorURL = nil
            clearSessions(resetTimestamp: true)
            errorMessage = nil
            isLoading = false
            return
        }

        activeServerIdentifier = connectionStore.settings.selectedServerIdentifier
        activeAccountScope = connectionStore.accountCacheScope
        guard !isSystemAsleep else { return }
        startMonitorTask()
        startConnectionRecheckTask()
        scheduleActivityRefresh(at: activityClock.now())
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
                try Task.checkCancellation()
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
                return
            } catch {
                guard !Task.isCancelled else { return }
                activeMonitorURL = nil
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                activityErrorMessage = errorMessage
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
        try Task.checkCancellation()
        guard configuration.accountCacheScope == connectionStore.accountCacheScope else {
            throw CancellationError()
        }
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

        if hydration != nil {
            hydrationNotifications.append(notification)
        }

        if notification.state?.lowercased() == "stopped" {
            removeSession(for: sessionKey)
            return
        }

        guard let existingSession = sessionsByKey[sessionKey] else {
            try await hydrateAll(using: configuration, showLoading: false, afterPlaybackChange: true)
            return
        }

        if notification.requiresHydrate(comparedTo: existingSession) {
            try await hydrateAll(using: configuration, showLoading: false, afterPlaybackChange: true)
            return
        }

        sessionsByKey[sessionKey] = existingSession.applying(playNotification: notification)
        refreshResolvedLocationsIfNeeded()
        errorMessage = nil
        lastUpdated = Date()
    }

    private func performFullHydrate(showLoading: Bool = true) async {
        guard !Task.isCancelled, !isSystemAsleep else { return }
        guard connectionStore.settings.hasValidConfiguration else {
            clearSessions(resetTimestamp: true)
            errorMessage = nil
            isLoading = false
            return
        }

        if monitorTask == nil || activeServerIdentifier != connectionStore.settings.selectedServerIdentifier {
            didChangeConfiguration()
        }

        let scope = connectionStore.accountCacheScope
        do {
            try await connectionStore.perform { configuration in
                try Task.checkCancellation()
                try await hydrateAll(using: configuration, showLoading: showLoading)
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled, scope == connectionStore.accountCacheScope else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            activityErrorMessage = errorMessage
        }
    }

    private func hydrateAll(
        using configuration: PlexConnectionConfiguration,
        showLoading: Bool,
        afterPlaybackChange: Bool = false
    ) async throws {
        try Task.checkCancellation()
        guard !isSystemAsleep, configuration.accountCacheScope == connectionStore.accountCacheScope else {
            throw CancellationError()
        }
        if let current = hydration,
           current.scope != configuration.accountCacheScope || current.url != configuration.serverURL {
            cancelHydration()
        }
        if let current = hydration {
            // An event received after a request began requires a snapshot taken
            // after that event. All waiters share the same reconciliation pass.
            if afterPlaybackChange { hydrationNeedsFollowup = true }
            if showLoading { isLoading = true }
            try await current.task.value
            return
        }

        let id = UUID()
        let task = Task { [weak self] in
            guard let self else { throw CancellationError() }
            defer {
                if self.hydration?.id == id {
                    self.hydration = nil
                    self.hydrationNotifications = []
                    self.hydrationNeedsFollowup = false
                    self.isLoading = false
                }
            }
            do {
                while true {
                    let fetched = try await self.client.fetchSessions(using: configuration)
                    try Task.checkCancellation()
                    guard self.hydration?.id == id,
                          configuration.accountCacheScope == self.connectionStore.accountCacheScope else {
                        throw CancellationError()
                    }
                    if self.hydrationNeedsFollowup {
                        self.hydrationNeedsFollowup = false
                        self.hydrationNotifications = []
                        continue
                    }
                    self.applyHydratedSessions(fetched)
                    return
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch {
                if self.hydration?.id == id,
                   configuration.accountCacheScope == self.connectionStore.accountCacheScope {
                    self.activityErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
                throw error
            }
        }
        hydration = (id, configuration.accountCacheScope, configuration.serverURL, task)
        isLoading = showLoading
        try await task.value
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

        // Preserve events newer than the HTTP request, including stops. A
        // completed fetch must not restore an old position or resurrect a session.
        for notification in hydrationNotifications {
            guard let key = notification.sessionKey?.nilIfBlank else { continue }
            if notification.state?.lowercased() == "stopped" {
                nextSessionsByKey.removeValue(forKey: key)
                nextSessionOrder.removeAll { $0 == key }
            } else if let session = nextSessionsByKey[key],
                      !notification.requiresHydrate(comparedTo: session) {
                nextSessionsByKey[key] = session.applying(playNotification: notification)
            }
        }
        sessionsByKey = nextSessionsByKey
        sessionOrder = nextSessionOrder
        pruneWaveformCache()
        refreshResolvedLocationsIfNeeded()
        errorMessage = nil
        lastUpdated = Date()
        lastHydratedAt = lastUpdated
        lastHydratedInstant = activityClock.now()
        activityErrorMessage = nil
        scheduleActivityRefresh(at: activityClock.now() + Self.activityRefreshInterval)
    }

    private func removeSession(for sessionKey: String) {
        sessionsByKey.removeValue(forKey: sessionKey)
        sessionOrder.removeAll { $0 == sessionKey }
        terminatingSessionKeys.remove(sessionKey)
        pruneWaveformCache()
        refreshResolvedLocationsIfNeeded()
        errorMessage = nil
        lastUpdated = Date()
    }

    private func clearSessions(resetTimestamp: Bool) {
        sessionsByKey = [:]
        sessionOrder = []
        terminatingSessionKeys.removeAll()
        pruneWaveformCache()
        refreshResolvedLocationsIfNeeded()

        if resetTimestamp {
            lastUpdated = nil
            lastHydratedAt = nil
            lastHydratedInstant = nil
            activityErrorMessage = nil
        }
    }

    private func reconnectBackoff(after attempt: Int) -> Duration {
        let seconds = min(max(1 << min(attempt, 4), 1), 30)
        return .seconds(seconds)
    }

    private func cancelBackgroundTasks() {
        cancelActivityRefresh()
        cancelHydration()
        monitorTask?.cancel()
        monitorTask = nil
        connectionRecheckTask?.cancel()
        connectionRecheckTask = nil
        geoLookupTasksByIP.values.forEach { $0.cancel() }
        geoLookupTasksByIP.removeAll()
        waveformLevelTasksByStreamID.values.forEach { $0.cancel() }
        waveformLevelTasksByStreamID.removeAll()
    }

    private func cancelHydration() {
        hydration?.task.cancel()
        hydration = nil
        hydrationNotifications = []
        hydrationNeedsFollowup = false
        isLoading = false
    }

    private func cancelActivityRefresh() {
        activityRefreshID = UUID()
        activityRefreshTask?.cancel()
        activityRefreshTask = nil
    }

    private func scheduleActivityRefresh(at deadline: ContinuousClock.Instant) {
        cancelActivityRefresh()
        guard !activityConsumers.isEmpty, !isSystemAsleep,
              connectionStore.settings.hasValidConfiguration else { return }
        let id = activityRefreshID
        let clock = activityClock
        activityRefreshTask = Task { [weak self] in
            do {
                try await clock.sleepUntil(deadline)
                try Task.checkCancellation()
            } catch { return }
            guard let self, self.activityRefreshID == id else { return }
            await self.performFullHydrate(showLoading: false)
            // Success schedules from the new snapshot. Failure waits for the
            // next regular interval; it never stamps old data as fresh.
            if self.activityRefreshID == id {
                self.scheduleActivityRefresh(at: clock.now() + Self.activityRefreshInterval)
            }
        }
    }

    private func startMonitorTask() {
        monitorTask?.cancel()
        activeMonitorURL = nil
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

    private func clearWaveformCache() {
        waveformLevelTasksByStreamID.values.forEach { $0.cancel() }
        waveformLevelTasksByStreamID.removeAll()
        waveformLevelsByStreamID.removeAll()
        waveformUnavailableStreamIDs.removeAll()
    }

    private func finishWaveformLoad(streamID: Int, levels: [Double]?) {
        waveformLevelTasksByStreamID.removeValue(forKey: streamID)

        guard let levels, !levels.isEmpty else {
            waveformUnavailableStreamIDs.insert(streamID)
            return
        }

        waveformLevelsByStreamID[streamID] = levels
    }

    private func finishCancelledWaveformLoad(streamID: Int) {
        waveformLevelTasksByStreamID.removeValue(forKey: streamID)
    }

    private func pruneWaveformCache() {
        let activeStreamIDs = Set(sessionsByKey.values.compactMap(\.audioStreamID))

        waveformLevelsByStreamID = waveformLevelsByStreamID.filter { activeStreamIDs.contains($0.key) }
        waveformUnavailableStreamIDs = waveformUnavailableStreamIDs.filter { activeStreamIDs.contains($0) }

        for streamID in waveformLevelTasksByStreamID.keys where !activeStreamIDs.contains(streamID) {
            waveformLevelTasksByStreamID[streamID]?.cancel()
            waveformLevelTasksByStreamID.removeValue(forKey: streamID)
        }
    }
}

private enum PlexSessionStoreError: LocalizedError {
    case missingSessionKey
    case missingServerSessionID

    var errorDescription: String? {
        switch self {
        case .missingSessionKey:
            return "Unable to terminate session: missing Plex session key."
        case .missingServerSessionID:
            return "Unable to terminate session: missing Plex session id."
        }
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
