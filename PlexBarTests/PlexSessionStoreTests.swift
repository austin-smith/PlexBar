@testable import PlexClientKit
import PlexModels
import AppKit
import Foundation
import Testing
@testable import PlexBar

@Suite(.serialized)
struct PlexSessionStoreTests {
@MainActor
@Test func websocketConnectPerformsOneFullHydrate() async throws {
    let suiteName = "PlexBarTests.websocketConnectPerformsOneFullHydrate"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let fullHydrateCounter = RequestCounter()
    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)

        if url.path == "/identity" {
            return try identityResponse(for: url)
        }

        if url.path == "/status/sessions", url.query == nil {
            fullHydrateCounter.increment()
            return try sessionsResponse(for: url, metadata: [sessionJSON(sessionKey: "44", ratingKey: "900", state: "playing", viewOffset: 1000)])
        }

        throw URLError(.unsupportedURL)
    }

    let settings = makeSessionStoreSettings(defaults: defaults)
    let store = makeSessionStore(
        settings: settings,
        session: session,
        eventsClient: PlexSessionEventsClient { _, onEvent in
            try await onEvent(.connected)
            try await Task.sleep(for: .seconds(60))
        }
    )
    defer { stopSessionMonitoring(store: store, settings: settings) }

    await waitForSessionStore(store) { $0.activeStreamCount == 1 }

    #expect(fullHydrateCounter.value == 1)
}

@MainActor
@Test func activityPollingSharesVisibilityAndStopsWhenHidden() async throws {
    let fixture = try ActivityRefreshFixture()
    defer { fixture.stop() }
    await fixture.ready()
    let first = UUID(), second = UUID()
    fixture.store.setActivityVisible(true, consumer: first)
    fixture.store.setActivityVisible(true, consumer: second)
    await waitUntil { fixture.clock.pendingCount == 1 }
    #expect(fixture.requests.value == 1)
    fixture.clock.advance(by: .seconds(9))
    #expect(fixture.requests.value == 1)
    fixture.clock.advance(by: .seconds(1))
    await waitUntil { fixture.requests.value == 2 && fixture.clock.pendingCount == 1 }
    #expect(fixture.requests.value == 2)
    fixture.store.setActivityVisible(false, consumer: first)
    fixture.clock.advance(by: .seconds(10))
    await waitUntil { fixture.requests.value == 3 && fixture.clock.pendingCount == 1 }
    #expect(fixture.requests.value == 3)
    fixture.store.setActivityVisible(false, consumer: second)
    await waitUntil { fixture.clock.pendingCount == 0 }
    #expect(fixture.clock.pendingCount == 0)
    fixture.clock.advance(by: .seconds(100))
    #expect(fixture.requests.value == 3)
    fixture.store.setActivityVisible(true, consumer: first)
    await waitUntil { fixture.requests.value == 4 && fixture.clock.pendingCount == 1 }
    #expect(fixture.requests.value == 4)
}

@MainActor
@Test(arguments: [true, false])
func activityPollingRefreshesUnchangedPausedAndEmptySnapshots(empty: Bool) async throws {
    let fixture = try ActivityRefreshFixture(empty: empty)
    defer { fixture.stop() }
    await fixture.ready()
    let original = try #require(fixture.store.lastHydratedAt)
    fixture.store.setActivityVisible(true, consumer: UUID())
    await waitUntil { fixture.clock.pendingCount == 1 }
    fixture.clock.advance(by: .seconds(10))
    await waitForSessionStore(fixture.store) { $0.lastHydratedAt != original }
    #expect(try #require(fixture.store.lastHydratedAt) > original)
    #expect(fixture.store.activeStreamCount == (empty ? 0 : 1))
    #expect(fixture.store.activitySummary.totalBandwidthKbps == (empty ? 0 : 8000))
    #expect(!fixture.store.isLoading)
}

@MainActor
@Test func activityPollingPreservesFailedSnapshotAndRecovers() async throws {
    let fixture = try ActivityRefreshFixture()
    defer { fixture.stop() }
    await fixture.ready()
    let original = try #require(fixture.store.lastHydratedAt)
    fixture.store.setActivityVisible(true, consumer: UUID())
    await waitUntil { fixture.clock.pendingCount == 1 }
    fixture.invalidResponse.withValue { $0 = true }
    fixture.clock.advance(by: .seconds(10))
    await waitUntil { fixture.store.activityErrorMessage != nil && fixture.clock.pendingCount == 1 }
    #expect(fixture.store.activityErrorMessage != nil)
    #expect(fixture.store.lastHydratedAt == original)
    #expect(fixture.store.activitySummary.totalBandwidthKbps == 8000)
    #expect(!fixture.store.isLoading)
    fixture.invalidResponse.withValue { $0 = false }
    fixture.bandwidth.withValue { $0 = 12000 }
    fixture.clock.advance(by: .seconds(10))
    await waitForSessionStore(fixture.store) { $0.activitySummary.totalBandwidthKbps == 12000 }
    #expect(fixture.store.activitySummary.totalBandwidthKbps == 12000)
    #expect(fixture.store.activityErrorMessage == nil)
    #expect(try #require(fixture.store.lastHydratedAt) > original)
    #expect(fixture.requests.value == 3)
}

@MainActor
@Test func manualRefreshJoinsActivityPollInFlight() async throws {
    let gate = DispatchSemaphore(value: 0)
    let fixture = try ActivityRefreshFixture(beforeResponse: { count in
        if count == 2 { #expect(gate.wait(timeout: .now() + 5) == .success) }
    })
    defer { gate.signal(); fixture.stop() }
    await fixture.ready()
    fixture.store.setActivityVisible(true, consumer: UUID())
    await waitUntil { fixture.clock.pendingCount == 1 }
    fixture.clock.advance(by: .seconds(10))
    await waitUntil { fixture.requests.value == 2 }
    #expect(!fixture.store.isLoading)
    let manual = fixture.store.refreshNow()
    await waitForSessionStore(fixture.store) { $0.isLoading }
    #expect(fixture.store.isLoading)
    gate.signal()
    await manual.value
    #expect(fixture.requests.value == 2)
    #expect(!fixture.store.isLoading)
}

@MainActor
@Test(arguments: ["stopped", "paused"])
func activitySnapshotPreservesNewerPlaybackEvents(state: String) async throws {
    let gate = DispatchSemaphore(value: 0)
    let fixture = try ActivityRefreshFixture(beforeResponse: { count in
        if count == 2 { #expect(gate.wait(timeout: .now() + 5) == .success) }
    })
    defer { gate.signal(); fixture.stop() }
    await fixture.ready()
    let original = try #require(fixture.store.lastHydratedAt)
    fixture.store.setActivityVisible(true, consumer: UUID())
    await waitUntil { fixture.clock.pendingCount == 1 }
    fixture.clock.advance(by: .seconds(10))
    await waitUntil { fixture.requests.value == 2 }
    let notification = try JSONDecoder().decode(PlexPlaySessionStateNotification.self, from: Data("""
        {"sessionKey":"44","state":"\(state)","viewOffset":9000}
        """.utf8))
    let handler = try #require(fixture.handler.value)
    try await handler(.playing(notification))
    gate.signal()
    await waitForSessionStore(fixture.store) { $0.lastHydratedAt != original }
    #expect(fixture.store.lastHydratedAt != original)
    if state == "stopped" {
        #expect(fixture.store.sessions.isEmpty)
        #expect(fixture.store.activitySummary.totalBandwidthKbps == 0)
    } else {
        #expect(fixture.store.sessions.first?.isPaused == true)
        #expect(fixture.store.sessions.first?.viewOffset == 9000)
    }
    #expect(fixture.requests.value == 2)
}

@MainActor
@Test func activityPollingCancelsOnSleepAndRefreshesOnWake() async throws {
    let fixture = try ActivityRefreshFixture()
    defer { fixture.stop() }
    await fixture.ready()
    fixture.store.setActivityVisible(true, consumer: UUID())
    await waitUntil { fixture.clock.pendingCount == 1 }
    fixture.store.systemWillSleep()
    await waitUntil { fixture.clock.pendingCount == 0 }
    #expect(fixture.clock.pendingCount == 0)
    fixture.clock.advance(by: .seconds(100))
    #expect(fixture.requests.value == 1)
    fixture.store.systemDidWake()
    await waitUntil { fixture.requests.value >= 2 && fixture.clock.pendingCount == 1 }
    #expect(fixture.requests.value >= 2)
    #expect(fixture.clock.pendingCount == 1)
}

@MainActor
@Test func activityPollingDiscardsResponseAfterSignOut() async throws {
    let gate = DispatchSemaphore(value: 0)
    let fixture = try ActivityRefreshFixture(beforeResponse: { count in
        if count == 2 { #expect(gate.wait(timeout: .now() + 5) == .success) }
    })
    defer { gate.signal(); fixture.stop() }
    await fixture.ready()
    let manual = fixture.store.refreshNow()
    await waitUntil { fixture.requests.value == 2 }
    fixture.stop()
    gate.signal()
    await manual.value
    #expect(fixture.store.sessions.isEmpty)
    #expect(fixture.store.lastHydratedAt == nil)
    #expect(fixture.store.activityErrorMessage == nil)
    #expect(!fixture.store.isLoading)
    #expect(fixture.clock.pendingCount == 0)
}

@MainActor
@Test func activityVisibilityObservesHostingWindowsAndPanelLifetime() async throws {
    let fixture = try ActivityRefreshFixture()
    defer { fixture.stop() }
    await fixture.ready()
    let first = UUID(), second = UUID()
    let window = ActivityVisibilityTestWindow()
    let panel = ActivityVisibilityTestWindow()
    let firstView = PlexActivityVisibilityView()
    let secondView = PlexActivityVisibilityView()
    firstView.isEnabled = true
    secondView.isEnabled = true
    firstView.onChange = { fixture.store.setActivityVisible($0, consumer: first) }
    secondView.onChange = { fixture.store.setActivityVisible($0, consumer: second) }
    window.contentView = firstView
    panel.contentView = secondView
    defer { firstView.stopObserving(); secondView.stopObserving() }
    window.setVisible(true)
    await waitUntil { fixture.clock.pendingCount == 1 }
    #expect(fixture.clock.pendingCount == 1)
    #expect(!window.isKeyWindow)
    panel.setVisible(true)
    // Flush the queued native visibility callbacks before hiding the first window.
    await Task { @MainActor in }.value
    window.setVisible(false)
    await Task { @MainActor in }.value
    #expect(fixture.clock.pendingCount == 1)
    panel.setVisible(false)
    await waitUntil { fixture.clock.pendingCount == 0 }
    #expect(fixture.clock.pendingCount == 0)
    fixture.clock.advance(by: .seconds(100))
    panel.setVisible(true)
    await waitUntil { fixture.requests.value == 2 && fixture.clock.pendingCount == 1 }
    #expect(fixture.requests.value == 2)
    secondView.isEnabled = false
    secondView.scheduleVisibilityUpdate()
    await waitUntil { fixture.clock.pendingCount == 0 }
    #expect(fixture.clock.pendingCount == 0)
    secondView.isEnabled = true
    secondView.scheduleVisibilityUpdate()
    await waitUntil { fixture.clock.pendingCount == 1 }
    secondView.stopObserving()
    await waitUntil { fixture.clock.pendingCount == 0 }
    #expect(fixture.clock.pendingCount == 0)
}

@MainActor
@Test func fullHydrateDropsSessionsWithoutCanonicalSessionKeys() async throws {
    let suiteName = "PlexBarTests.fullHydrateDropsSessionsWithoutCanonicalSessionKeys"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)

        if url.path == "/identity" {
            return try identityResponse(for: url)
        }

        if url.path == "/status/sessions", url.query == nil {
            return try sessionsResponse(for: url, metadata: [
                sessionJSONWithoutCanonicalKey(
                    ratingKey: "900",
                    state: "playing",
                    viewOffset: 1000
                )
            ])
        }

        throw URLError(.unsupportedURL)
    }

    let settings = makeSessionStoreSettings(defaults: defaults)
    let store = makeSessionStore(
        settings: settings,
        session: session,
        eventsClient: PlexSessionEventsClient { _, onEvent in
            try await onEvent(.connected)
            try await Task.sleep(for: .seconds(60))
        }
    )
    defer { stopSessionMonitoring(store: store, settings: settings) }

    await waitForSessionStore(store) {
        $0.lastUpdated != nil
    }

    #expect(store.activeStreamCount == 0)
}

@MainActor
@Test func configurationChangeClearsUnavailableWaveformCache() async throws {
    let suiteName = "PlexBarTests.configurationChangeClearsUnavailableWaveformCache"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let levelsRequestCounter = RequestCounter()
    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)

        if url.path == "/identity" {
            return try identityResponse(for: url)
        }

        if url.path == "/status/sessions", url.query == nil {
            return try sessionsResponse(for: url, metadata: [
                trackSessionJSON(sessionKey: "44", ratingKey: "900", state: "playing", viewOffset: 1000, streamID: 123)
            ])
        }

        if url.path == "/library/streams/123/levels" {
            levelsRequestCounter.increment()
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"{"error":"not found"}"#.data(using: .utf8))
            return (response, data)
        }

        throw URLError(.unsupportedURL)
    }

    let settings = makeSessionStoreSettings(defaults: defaults)
    let store = makeSessionStore(
        settings: settings,
        session: session,
        eventsClient: PlexSessionEventsClient { _, onEvent in
            try await onEvent(.connected)
            try await Task.sleep(for: .seconds(60))
        }
    )
    defer { stopSessionMonitoring(store: store, settings: settings) }

    await waitForSessionStore(store) { $0.activeStreamCount == 1 }
    let trackSession = try #require(store.sessions.first)

    store.loadWaveformLevelsIfNeeded(for: trackSession)
    await waitUntil { levelsRequestCounter.value == 1 }

    store.loadWaveformLevelsIfNeeded(for: trackSession)
    try await Task.sleep(for: .milliseconds(50))
    #expect(levelsRequestCounter.value == 1)

    store.didChangeConfiguration()
    store.loadWaveformLevelsIfNeeded(for: trackSession)
    await waitUntil { levelsRequestCounter.value == 2 }
}

@MainActor
@Test func cancelledWaveformLoadDoesNotMarkStreamUnavailable() async throws {
    let suiteName = "PlexBarTests.cancelledWaveformLoadDoesNotMarkStreamUnavailable"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let levelsRequestCounter = RequestCounter()
    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)

        if url.path == "/identity" {
            return try identityResponse(for: url)
        }

        if url.path == "/status/sessions", url.query == nil {
            return try sessionsResponse(for: url, metadata: [
                trackSessionJSON(sessionKey: "44", ratingKey: "900", state: "playing", viewOffset: 1000, streamID: 123)
            ])
        }

        if url.path == "/library/streams/123/levels" {
            levelsRequestCounter.increment()

            if levelsRequestCounter.value == 1 {
                throw CancellationError()
            }

            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"""
            {
              "MediaContainer": {
                "Level": [
                  { "v": -27.0 },
                  { "v": -26.0 }
                ]
              }
            }
            """#.data(using: .utf8))
            return (response, data)
        }

        throw URLError(.unsupportedURL)
    }

    let settings = makeSessionStoreSettings(defaults: defaults)
    let store = makeSessionStore(
        settings: settings,
        session: session,
        eventsClient: PlexSessionEventsClient { _, onEvent in
            try await onEvent(.connected)
            try await Task.sleep(for: .seconds(60))
        }
    )
    defer { stopSessionMonitoring(store: store, settings: settings) }

    await waitForSessionStore(store) { $0.activeStreamCount == 1 }
    let trackSession = try #require(store.sessions.first)

    store.loadWaveformLevelsIfNeeded(for: trackSession)
    await waitUntil { levelsRequestCounter.value == 1 }
    await waitUntil { store.waveformLevels(for: trackSession) == nil }

    store.loadWaveformLevelsIfNeeded(for: trackSession)
    await waitUntil { levelsRequestCounter.value == 2 }
    await waitUntil { store.waveformLevels(for: trackSession) == [-27.0, -26.0] }
}

@MainActor
@Test func startupWaitsForServerRefreshBeforeStartingMonitor() async throws {
    let suiteName = "PlexBarTests.startupWaitsForServerRefreshBeforeStartingMonitor"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let monitorURLs = Locked<[URL]>([])
    let remoteURL = try #require(URL(string: "https://plex.remote:32400"))
    let localURL = try #require(URL(string: "https://plex.local:32400"))
    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)

        if url.path == "/identity" {
            return try identityResponse(for: url)
        }

        if url.path == "/status/sessions", url.host == "plex.local" {
            return try sessionsResponse(for: url, metadata: [
                sessionJSON(sessionKey: "55", ratingKey: "901", state: "playing", viewOffset: 2000)
            ])
        }

        throw URLError(.unsupportedURL)
    }

    let server = PlexServerResource(
        id: "server-id",
        name: "Server",
        productVersion: nil,
        accessToken: "server-token",
        connections: [
            PlexServerConnection(uri: localURL, local: true, relay: false),
            PlexServerConnection(uri: remoteURL, local: false, relay: false)
        ]
    )

    let settings = makeSessionStoreSettings(defaults: defaults)
    settings.cachedConnectionURLString = remoteURL.absoluteString
    settings.cachedConnectionKind = .remote
    settings.connectionRecheckIntervalSeconds = 0

    let resolver = PlexConnectionResolver(
        client: PlexAPIClient(session: session),
        probeTimeoutInterval: 0.1
    )
    let connectionStore = PlexConnectionStore(
        settings: settings,
        resolver: resolver
    )
    let store = PlexSessionStore(
        connectionStore: connectionStore,
        client: PlexAPIClient(session: session),
        eventsClient: PlexSessionEventsClient { configuration, onEvent in
            monitorURLs.withValue { $0.append(configuration.serverURL) }
            try await onEvent(.connected)
            try await Task.sleep(for: .seconds(60))
        }
    )
    defer { stopSessionMonitoring(store: store, settings: settings) }

    try? await Task.sleep(nanoseconds: 50_000_000)
    #expect(monitorURLs.value.isEmpty)

    connectionStore.updateAvailableServers([server])
    store.didChangeConfiguration()

    await waitForSessionStore(store) {
        $0.sessions.first?.canonicalSessionKey == "55"
    }

    let seenURLs = monitorURLs.value
    #expect(seenURLs == [localURL])
}

@MainActor
@Test func knownPlayingEventUpdatesInMemoryWithoutHttp() async throws {
    let suiteName = "PlexBarTests.knownPlayingEventUpdatesInMemoryWithoutHttp"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let fullHydrateCounter = RequestCounter()
    let targetedHydrateCounter = RequestCounter()
    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)

        if url.path == "/identity" {
            return try identityResponse(for: url)
        }

        if url.path == "/status/sessions", url.query == nil {
            fullHydrateCounter.increment()
            return try sessionsResponse(for: url, metadata: [sessionJSON(sessionKey: "44", ratingKey: "900", state: "playing", viewOffset: 1000)])
        }

        if url.path == "/status/sessions", url.query?.contains("sessionKey=") == true {
            targetedHydrateCounter.increment()
            return try sessionsResponse(for: url, metadata: [])
        }

        throw URLError(.unsupportedURL)
    }

    let settings = makeSessionStoreSettings(defaults: defaults)
    let store = makeSessionStore(
        settings: settings,
        session: session,
        eventsClient: PlexSessionEventsClient { _, onEvent in
            try await onEvent(.connected)
            try await onEvent(.playing(PlexPlaySessionStateNotification(
                sessionKey: "44",
                state: "paused",
                viewOffset: 2500,
                ratingKey: "900",
                key: "/library/metadata/900",
                transcodeSessionKey: nil
            )))
            try await Task.sleep(for: .seconds(60))
        }
    )
    defer { stopSessionMonitoring(store: store, settings: settings) }

    await waitForSessionStore(store) {
        $0.sessions.first?.viewOffset == 2500 && $0.sessions.first?.isPaused == true
    }

    #expect(store.activitySummary.streamCount == 1)
    #expect(store.lastHydratedAt != nil)
    #expect(store.lastUpdated != store.lastHydratedAt)
    #expect(fullHydrateCounter.value == 1)
    #expect(targetedHydrateCounter.value == 0)
}

@MainActor
@Test func terminateSessionPostsToPlexAndRemovesSession() async throws {
    let suiteName = "PlexBarTests.terminateSessionPostsToPlexAndRemovesSession"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let requestCapture = RequestCapture()
    let sessionsCounter = RequestCounter()
    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)

        if url.path == "/identity" {
            return try identityResponse(for: url)
        }

        if url.path == "/status/sessions", url.query == nil {
            sessionsCounter.increment()
            let metadata = sessionsCounter.value == 1
                ? [sessionJSON(sessionKey: "44", ratingKey: "900", state: "playing", viewOffset: 1000)]
                : []
            return try sessionsResponse(for: url, metadata: metadata)
        }

        if url.path == "/status/sessions/terminate" {
            requestCapture.record(request)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"{}"#.data(using: .utf8))
            return (response, data)
        }

        throw URLError(.unsupportedURL)
    }

    let settings = makeSessionStoreSettings(defaults: defaults)
    let store = makeSessionStore(
        settings: settings,
        session: session,
        eventsClient: PlexSessionEventsClient { _, onEvent in
            try await onEvent(.connected)
            try await Task.sleep(for: .seconds(60))
        }
    )
    defer { stopSessionMonitoring(store: store, settings: settings) }

    await waitForSessionStore(store) { $0.activeStreamCount == 1 }

    await store.terminate(try #require(store.sessions.first))

    #expect(store.activeStreamCount == 0)

    let request = try #require(requestCapture.request)
    #expect(request.httpMethod == "POST")

    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    #expect(components.path == "/status/sessions/terminate")
    #expect(queryItems["sessionId"] == "44")
    #expect(queryItems["reason"] == nil)
}

@MainActor
@Test func terminateSessionMarksSessionAsStoppingWhileRequestIsInFlight() async throws {
    let suiteName = "PlexBarTests.terminateSessionMarksSessionAsStoppingWhileRequestIsInFlight"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let terminateRequestStarted = RequestCounter()
    let sessionsCounter = RequestCounter()
    let terminateGate = DispatchSemaphore(value: 0)
    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)

        if url.path == "/identity" {
            return try identityResponse(for: url)
        }

        if url.path == "/status/sessions", url.query == nil {
            sessionsCounter.increment()
            let metadata = sessionsCounter.value == 1
                ? [sessionJSON(sessionKey: "44", ratingKey: "900", state: "playing", viewOffset: 1000)]
                : []
            return try sessionsResponse(for: url, metadata: metadata)
        }

        if url.path == "/status/sessions/terminate" {
            terminateRequestStarted.increment()
            terminateGate.wait()

            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"{}"#.data(using: .utf8))
            return (response, data)
        }

        throw URLError(.unsupportedURL)
    }

    let settings = makeSessionStoreSettings(defaults: defaults)
    let store = makeSessionStore(
        settings: settings,
        session: session,
        eventsClient: PlexSessionEventsClient { _, onEvent in
            try await onEvent(.connected)
            try await Task.sleep(for: .seconds(60))
        }
    )
    defer { stopSessionMonitoring(store: store, settings: settings) }

    await waitForSessionStore(store) { $0.activeStreamCount == 1 }
    let activeSession = try #require(store.sessions.first)

    let terminateTask = Task {
        await store.terminate(activeSession)
    }

    await waitForSessionStore(store) {
        terminateRequestStarted.value == 1 && $0.activeStreamCount == 1 && $0.isTerminating(activeSession)
    }

    terminateGate.signal()
    await terminateTask.value

    #expect(store.activeStreamCount == 0)
}

@MainActor
@Test func terminateSessionClearsStoppingStateWhenRefreshStillReturnsSession() async throws {
    let suiteName = "PlexBarTests.terminateSessionClearsStoppingStateWhenRefreshStillReturnsSession"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let sessionsCounter = RequestCounter()
    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)

        if url.path == "/identity" {
            return try identityResponse(for: url)
        }

        if url.path == "/status/sessions", url.query == nil {
            sessionsCounter.increment()
            return try sessionsResponse(
                for: url,
                metadata: [sessionJSON(sessionKey: "44", ratingKey: "900", state: "playing", viewOffset: 1000)]
            )
        }

        if url.path == "/status/sessions/terminate" {
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"{}"#.data(using: .utf8))
            return (response, data)
        }

        throw URLError(.unsupportedURL)
    }

    let settings = makeSessionStoreSettings(defaults: defaults)
    let store = makeSessionStore(
        settings: settings,
        session: session,
        eventsClient: PlexSessionEventsClient { _, onEvent in
            try await onEvent(.connected)
            try await Task.sleep(for: .seconds(60))
        }
    )
    defer { stopSessionMonitoring(store: store, settings: settings) }

    await waitForSessionStore(store) { $0.activeStreamCount == 1 }
    let activeSession = try #require(store.sessions.first)

    await store.terminate(activeSession)

    #expect(store.activeStreamCount == 1)
    #expect(store.isTerminating(activeSession) == false)
    #expect(sessionsCounter.value >= 2)
}

@MainActor
@Test func terminateSessionClearsStoppingStateWhenRefreshFails() async throws {
    let suiteName = "PlexBarTests.terminateSessionClearsStoppingStateWhenRefreshFails"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let sessionsCounter = RequestCounter()
    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)

        if url.path == "/identity" {
            return try identityResponse(for: url)
        }

        if url.path == "/status/sessions", url.query == nil {
            sessionsCounter.increment()

            if sessionsCounter.value == 1 {
                return try sessionsResponse(
                    for: url,
                    metadata: [sessionJSON(sessionKey: "44", ratingKey: "900", state: "playing", viewOffset: 1000)]
                )
            }

            throw URLError(.timedOut)
        }

        if url.path == "/status/sessions/terminate" {
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"{}"#.data(using: .utf8))
            return (response, data)
        }

        throw URLError(.unsupportedURL)
    }

    let settings = makeSessionStoreSettings(defaults: defaults)
    let store = makeSessionStore(
        settings: settings,
        session: session,
        eventsClient: PlexSessionEventsClient { _, onEvent in
            try await onEvent(.connected)
            try await Task.sleep(for: .seconds(60))
        }
    )
    defer { stopSessionMonitoring(store: store, settings: settings) }

    await waitForSessionStore(store) { $0.activeStreamCount == 1 }
    let activeSession = try #require(store.sessions.first)

    let retrievedAt = store.lastHydratedAt
    await store.terminate(activeSession)

    #expect(store.activeStreamCount == 1)
    #expect(store.isTerminating(activeSession) == false)
    #expect(store.errorMessage?.isEmpty == false)
    #expect(sessionsCounter.value >= 2)
    #expect(store.activityErrorMessage != nil)
    #expect(store.lastHydratedAt == retrievedAt)
    #expect(store.activitySummary.streamCount == 1)
}

@MainActor
@Test func terminateSessionDoesNotRetryPostOnConnectivityFailure() async throws {
    let suiteName = "PlexBarTests.terminateSessionDoesNotRetryPostOnConnectivityFailure"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let terminateCounter = RequestCounter()
    let sessionsCounter = RequestCounter()
    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)

        if url.path == "/identity" {
            return try identityResponse(for: url)
        }

        if url.path == "/status/sessions", url.query == nil {
            sessionsCounter.increment()
            return try sessionsResponse(
                for: url,
                metadata: [sessionJSON(sessionKey: "44", ratingKey: "900", state: "playing", viewOffset: 1000)]
            )
        }

        if url.path == "/status/sessions/terminate" {
            terminateCounter.increment()
            throw URLError(.networkConnectionLost)
        }

        throw URLError(.unsupportedURL)
    }

    let settings = makeSessionStoreSettings(defaults: defaults)
    let store = makeSessionStore(
        settings: settings,
        session: session,
        eventsClient: PlexSessionEventsClient { _, onEvent in
            try await onEvent(.connected)
            try await Task.sleep(for: .seconds(60))
        }
    )
    defer { stopSessionMonitoring(store: store, settings: settings) }

    await waitForSessionStore(store) { $0.activeStreamCount == 1 }
    let activeSession = try #require(store.sessions.first)

    await store.terminate(activeSession)

    #expect(terminateCounter.value == 1)
    #expect(store.activeStreamCount == 1)
    #expect(store.isTerminating(activeSession) == false)
    #expect(store.errorMessage?.isEmpty == false)
    #expect(sessionsCounter.value == 1)
    #expect(store.activityErrorMessage == nil)
}

@MainActor
@Test func terminateSessionUsesFreshResolvedConnectionWhenCachedConnectionTurnsStale() async throws {
    let suiteName = "PlexBarTests.terminateSessionUsesFreshResolvedConnectionWhenCachedConnectionTurnsStale"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let localURL = try #require(URL(string: "http://plex.local:32400"))
    let remoteURL = try #require(URL(string: "https://plex.remote:32400"))
    let staleLocal = Locked(false)
    let localTerminateCounter = RequestCounter()
    let remoteTerminateCounter = RequestCounter()
    let remoteSessionsCounter = RequestCounter()

    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)

        if url.path == "/identity" {
            if url.host == "plex.local", staleLocal.value {
                throw URLError(.timedOut)
            }

            return try identityResponse(for: url)
        }

        if url.path == "/status/sessions", url.query == nil {
            if url.host == "plex.local", staleLocal.value {
                throw URLError(.timedOut)
            }

            if url.host == "plex.remote" {
                remoteSessionsCounter.increment()
                return try sessionsResponse(for: url, metadata: [])
            }

            return try sessionsResponse(
                for: url,
                metadata: [sessionJSON(sessionKey: "44", ratingKey: "900", state: "playing", viewOffset: 1000)]
            )
        }

        if url.path == "/status/sessions/terminate" {
            if url.host == "plex.local" {
                localTerminateCounter.increment()
                throw URLError(.timedOut)
            }

            if url.host == "plex.remote" {
                remoteTerminateCounter.increment()
                let response = try #require(HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                ))
                let data = try #require(#"{}"#.data(using: .utf8))
                return (response, data)
            }
        }

        throw URLError(.unsupportedURL)
    }

    let settings = makeSessionStoreSettings(defaults: defaults)
    settings.cachedConnectionURLString = localURL.absoluteString
    settings.cachedConnectionKind = .local

    let resolver = PlexConnectionResolver(
        client: PlexAPIClient(session: session),
        probeTimeoutInterval: 0.1
    )
    let connectionStore = PlexConnectionStore(
        settings: settings,
        resolver: resolver
    )
    let initialServer = PlexServerResource(
        id: "server-id",
        name: "Server",
        productVersion: nil,
        accessToken: "server-token",
        connections: [
            PlexServerConnection(uri: localURL, local: true, relay: false)
        ]
    )
    connectionStore.updateAvailableServers([initialServer])

    let store = PlexSessionStore(
        connectionStore: connectionStore,
        client: PlexAPIClient(session: session),
        eventsClient: PlexSessionEventsClient { _, onEvent in
            try await onEvent(.connected)
            try await Task.sleep(for: .seconds(60))
        }
    )
    defer { stopSessionMonitoring(store: store, settings: settings) }

    store.didChangeConfiguration()

    await waitForSessionStore(store) { $0.activeStreamCount == 1 }
    let activeSession = try #require(store.sessions.first)

    staleLocal.withValue { $0 = true }
    let upgradedServer = PlexServerResource(
        id: "server-id",
        name: "Server",
        productVersion: nil,
        accessToken: "server-token",
        connections: [
            PlexServerConnection(uri: localURL, local: true, relay: false),
            PlexServerConnection(uri: remoteURL, local: false, relay: false)
        ]
    )
    connectionStore.updateAvailableServers([upgradedServer])

    await store.terminate(activeSession)

    #expect(localTerminateCounter.value == 0)
    #expect(remoteTerminateCounter.value == 1)
    #expect(store.activeStreamCount == 0)
}

@MainActor
@Test func terminateSessionIncludesProvidedReason() async throws {
    let suiteName = "PlexBarTests.terminateSessionIncludesProvidedReason"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let requestCapture = RequestCapture()
    let sessionsCounter = RequestCounter()
    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)

        if url.path == "/identity" {
            return try identityResponse(for: url)
        }

        if url.path == "/status/sessions", url.query == nil {
            sessionsCounter.increment()
            let metadata = sessionsCounter.value == 1
                ? [sessionJSON(sessionKey: "44", ratingKey: "900", state: "playing", viewOffset: 1000)]
                : []
            return try sessionsResponse(for: url, metadata: metadata)
        }

        if url.path == "/status/sessions/terminate" {
            requestCapture.record(request)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"{}"#.data(using: .utf8))
            return (response, data)
        }

        throw URLError(.unsupportedURL)
    }

    let settings = makeSessionStoreSettings(defaults: defaults)
    let store = makeSessionStore(
        settings: settings,
        session: session,
        eventsClient: PlexSessionEventsClient { _, onEvent in
            try await onEvent(.connected)
            try await Task.sleep(for: .seconds(60))
        }
    )
    defer { stopSessionMonitoring(store: store, settings: settings) }

    await waitForSessionStore(store) { $0.activeStreamCount == 1 }

    await store.terminate(try #require(store.sessions.first), reason: "Stopped by admin")

    let request = try #require(requestCapture.request)
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    #expect(queryItems["reason"] == "Stopped by admin")
}

@MainActor
@Test func terminateSessionWithoutServerSessionIDSurfacesConcreteError() async throws {
    let suiteName = "PlexBarTests.terminateSessionWithoutServerSessionIDSurfacesConcreteError"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let terminateCounter = RequestCounter()
    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)

        if url.path == "/identity" {
            return try identityResponse(for: url)
        }

        if url.path == "/status/sessions", url.query == nil {
            return try sessionsResponse(for: url, metadata: [
                sessionJSON(
                    sessionKey: "44",
                    ratingKey: "900",
                    state: "playing",
                    viewOffset: 1000,
                    includeSessionID: false
                )
            ])
        }

        if url.path == "/status/sessions/terminate" {
            terminateCounter.increment()
        }

        throw URLError(.unsupportedURL)
    }

    let settings = makeSessionStoreSettings(defaults: defaults)
    let store = makeSessionStore(
        settings: settings,
        session: session,
        eventsClient: PlexSessionEventsClient { _, onEvent in
            try await onEvent(.connected)
            try await Task.sleep(for: .seconds(60))
        }
    )
    defer { stopSessionMonitoring(store: store, settings: settings) }

    await waitForSessionStore(store) { $0.activeStreamCount == 1 }

    await store.terminate(try #require(store.sessions.first))

    #expect(store.activeStreamCount == 1)
    #expect(store.errorMessage == "Unable to terminate session: missing Plex session id.")
    #expect(terminateCounter.value == 0)
}

@MainActor
@Test func lanSessionsResolveGeoLocationWhenPlexProvidesRemotePublicAddress() async throws {
    let suiteName = "PlexBarTests.lanSessionsResolveGeoLocationWhenPlexProvidesRemotePublicAddress"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let geoLookupCounter = RequestCounter()
    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)

        if url.host == "plex.tv", url.path == "/api/v2/geoip" {
            geoLookupCounter.increment()
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"""
            <?xml version="1.0" encoding="UTF-8"?>
            <MediaContainer size="1">
              <location city="Portland" subdivisions="Oregon" country="United States" code="US" />
            </MediaContainer>
            """#.data(using: .utf8))
            return (response, data)
        }

        if url.path == "/identity" {
            return try identityResponse(for: url)
        }

        if url.path == "/status/sessions", url.query == nil {
            return try sessionsResponse(for: url, metadata: [
                sessionJSON(
                    sessionKey: "44",
                    ratingKey: "900",
                    state: "playing",
                    viewOffset: 1000,
                    sessionLocation: "lan",
                    playerAddress: "192.168.1.226",
                    remotePublicAddress: "97.115.180.233",
                    playerLocal: true,
                    playerRelayed: false
                )
            ])
        }

        throw URLError(.unsupportedURL)
    }

    let settings = makeSessionStoreSettings(defaults: defaults)
    settings.userToken = "user-token"

    let store = makeSessionStore(
        settings: settings,
        session: session,
        geoIPClient: PlexGeoIPClient(session: session),
        eventsClient: PlexSessionEventsClient { _, onEvent in
            try await onEvent(.connected)
            try await Task.sleep(for: .seconds(60))
        }
    )
    defer { stopSessionMonitoring(store: store, settings: settings) }

    await waitForSessionStore(store) {
        guard let firstSession = $0.sessions.first else {
            return false
        }

        return $0.resolvedLocation(for: firstSession) == "Portland, Oregon"
    }

    #expect(geoLookupCounter.value == 1)

    store.refreshNow()

    await waitForSessionStore(store) {
        guard let firstSession = $0.sessions.first else {
            return false
        }

        return $0.resolvedLocation(for: firstSession) == "Portland, Oregon"
    }

    #expect(geoLookupCounter.value == 1)
}

@MainActor
@Test func transientGeoLookupFailuresAreRetriedOnLaterRefresh() async throws {
    let suiteName = "PlexBarTests.transientGeoLookupFailuresAreRetriedOnLaterRefresh"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let geoLookupCounter = RequestCounter()
    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)

        if url.host == "plex.tv", url.path == "/api/v2/geoip" {
            geoLookupCounter.increment()

            if geoLookupCounter.value == 1 {
                let response = try #require(HTTPURLResponse(
                    url: url,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: nil
                ))
                return (response, Data())
            }

            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"""
            <?xml version="1.0" encoding="UTF-8"?>
            <MediaContainer size="1">
              <location city="Portland" subdivisions="Oregon" country="United States" code="US" />
            </MediaContainer>
            """#.data(using: .utf8))
            return (response, data)
        }

        if url.path == "/identity" {
            return try identityResponse(for: url)
        }

        if url.path == "/status/sessions", url.query == nil {
            return try sessionsResponse(for: url, metadata: [
                sessionJSON(
                    sessionKey: "44",
                    ratingKey: "900",
                    state: "playing",
                    viewOffset: 1000,
                    sessionLocation: "lan",
                    playerAddress: "192.168.1.226",
                    remotePublicAddress: "97.115.180.233",
                    playerLocal: true,
                    playerRelayed: false
                )
            ])
        }

        throw URLError(.unsupportedURL)
    }

    let settings = makeSessionStoreSettings(defaults: defaults)
    settings.userToken = "user-token"

    let store = makeSessionStore(
        settings: settings,
        session: session,
        geoIPClient: PlexGeoIPClient(session: session),
        eventsClient: PlexSessionEventsClient { _, onEvent in
            try await onEvent(.connected)
            try await Task.sleep(for: .seconds(60))
        }
    )
    defer { stopSessionMonitoring(store: store, settings: settings) }

    await waitForSessionStore(store) {
        $0.sessions.count == 1 && geoLookupCounter.value == 1
    }

    #expect(store.resolvedLocation(for: try #require(store.sessions.first)) == nil)

    store.refreshNow()

    await waitForSessionStore(store) {
        guard let firstSession = $0.sessions.first else {
            return false
        }

        return $0.resolvedLocation(for: firstSession) == "Portland, Oregon"
    }

    #expect(geoLookupCounter.value == 2)
}

@MainActor
@Test func cancelledGeoLookupErrorsDoNotMarkIPUnavailable() async throws {
    let suiteName = "PlexBarTests.cancelledGeoLookupErrorsDoNotMarkIPUnavailable"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let geoLookupCounter = RequestCounter()
    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)

        if url.host == "plex.tv", url.path == "/api/v2/geoip" {
            geoLookupCounter.increment()

            if geoLookupCounter.value == 1 {
                throw URLError(.cancelled)
            }

            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let data = try #require(#"""
            <?xml version="1.0" encoding="UTF-8"?>
            <MediaContainer size="1">
              <location city="Portland" subdivisions="Oregon" country="United States" code="US" />
            </MediaContainer>
            """#.data(using: .utf8))
            return (response, data)
        }

        if url.path == "/identity" {
            return try identityResponse(for: url)
        }

        if url.path == "/status/sessions", url.query == nil {
            return try sessionsResponse(for: url, metadata: [
                sessionJSON(
                    sessionKey: "44",
                    ratingKey: "900",
                    state: "playing",
                    viewOffset: 1000,
                    sessionLocation: "lan",
                    playerAddress: "192.168.1.226",
                    remotePublicAddress: "97.115.180.233",
                    playerLocal: true,
                    playerRelayed: false
                )
            ])
        }

        throw URLError(.unsupportedURL)
    }

    let settings = makeSessionStoreSettings(defaults: defaults)
    settings.userToken = "user-token"

    let store = makeSessionStore(
        settings: settings,
        session: session,
        geoIPClient: PlexGeoIPClient(session: session),
        eventsClient: PlexSessionEventsClient { _, onEvent in
            try await onEvent(.connected)
            try await Task.sleep(for: .seconds(60))
        }
    )
    defer { stopSessionMonitoring(store: store, settings: settings) }

    await waitForSessionStore(store) {
        $0.sessions.count == 1 && geoLookupCounter.value == 1
    }

    #expect(store.resolvedLocation(for: try #require(store.sessions.first)) == nil)

    store.refreshNow()

    await waitForSessionStore(store) {
        guard let firstSession = $0.sessions.first else {
            return false
        }

        return $0.resolvedLocation(for: firstSession) == "Portland, Oregon"
    }

    #expect(geoLookupCounter.value == 2)
}

@MainActor
@Test(arguments: [true, false], [true, false])
func capturedEpisodeTransitionReconcilesSessions(
    receivesStop: Bool,
    startsWithTranscode: Bool
) async throws {
    let suiteName = "PlexBarTests.capturedEpisodeTransition.\(receivesStop).\(startsWithTranscode)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let requestCount = RequestCounter()
    let handler = Locked<PlexSessionEventsClient.MonitorHandler?>(nil)
    let pausedSession = sessionJSON(sessionKey: "90", ratingKey: "31475", state: "paused", viewOffset: 1574817)
    let oldEpisode = sessionJSON(
        sessionKey: "91", ratingKey: "2832", state: "playing", viewOffset: 1289000,
        transcodeSessionKey: "/transcode/sessions/transcode-old",
        type: "episode", title: "Episode 10"
    )
    let nextEpisode = sessionJSON(
        sessionKey: "92", ratingKey: "2833", state: "playing", viewOffset: 0,
        transcodeSessionKey: "/transcode/sessions/transcode-next",
        type: "episode", title: "Episode 11"
    )
    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)
        if url.path == "/identity" {
            return try identityResponse(for: url)
        }
        if url.path == "/status/sessions" {
            #expect(url.query == nil)
            requestCount.increment()
            let episode = requestCount.value == 1 ? oldEpisode : nextEpisode
            return try sessionsResponse(for: url, metadata: [pausedSession, episode])
        }
        throw URLError(.unsupportedURL)
    }
    let settings = makeSessionStoreSettings(defaults: defaults)
    let store = makeSessionStore(
        settings: settings,
        session: session,
        eventsClient: PlexSessionEventsClient { _, onEvent in
            try await onEvent(.connected)
            handler.withValue { $0 = onEvent }
            try await Task.sleep(for: .seconds(60))
        }
    )
    defer { stopSessionMonitoring(store: store, settings: settings) }
    await waitUntil { handler.value != nil }
    let onEvent = try #require(handler.value)
    #expect(store.sessions.map(\.canonicalSessionKey) == ["90", "91"])

    // Captured PMS stop/start/progress contracts; opaque transcode IDs are anonymized.
    if receivesStop {
        let stopped = Data(#"{"NotificationContainer":{"type":"playing","PlaySessionStateNotification":[{"key":"/library/metadata/2832","ratingKey":"2832","sessionKey":"91","state":"stopped","transcodeSession":"transcode-old","viewOffset":1294000}]}}"#.utf8)
        let events = PlexSessionEventsClient.decodeEventsIfPossible(from: stopped)
        #expect(events.count == 1)
        for event in events {
            try await onEvent(event)
        }
        #expect(store.sessions.map(\.canonicalSessionKey) == ["90"])
        #expect(requestCount.value == 1)
    }

    // The observed next-episode start omitted the field. Another real stream included it
    // from its first notification and never appeared before the decoder was corrected.
    let transcodeField = startsWithTranscode ? #", "transcodeSession":"transcode-next""# : ""
    let started = Data("""
    {"NotificationContainer":{"type":"playing","PlaySessionStateNotification":[
      {"key":"/library/metadata/2833","ratingKey":"2833","sessionKey":"92","state":"playing","viewOffset":0\(transcodeField)}
    ]}}
    """.utf8)
    let startEvents = PlexSessionEventsClient.decodeEventsIfPossible(from: started)
    #expect(startEvents.count == 1)
    for event in startEvents {
        try await onEvent(event)
        try await onEvent(event) // Duplicate start must not add a row or refetch.
    }

    for offset in [9000, 19000] {
        let progress = Data("""
        {"NotificationContainer":{"type":"playing","PlaySessionStateNotification":[
          {"key":"/library/metadata/2833","ratingKey":"2833","sessionKey":"92","state":"playing","transcodeSession":"transcode-next","viewOffset":\(offset)}
        ]}}
        """.utf8)
        let events = PlexSessionEventsClient.decodeEventsIfPossible(from: progress)
        #expect(events.count == 1)
        for event in events {
            try await onEvent(event)
        }
    }

    #expect(store.sessions.map(\.canonicalSessionKey) == ["90", "92"])
    #expect(store.sessions.first?.isPaused == true)
    #expect(store.sessions.first?.viewOffset == 1574817)
    #expect(store.sessions.last?.title == "Episode 11")
    #expect(store.sessions.last?.viewOffset == 19000)
    #expect(store.sessions.last?.transcodeSessionKey == "/transcode/sessions/transcode-next")
    #expect(store.activeStreamCount == 2)
    #expect(store.errorMessage == nil)
    #expect(requestCount.value == 2)
}

@MainActor
@Test func unknownPlayingEventRefreshesTheActiveSessionList() async throws {
    let suiteName = "PlexBarTests.unknownPlayingEventRefreshesTheActiveSessionList"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let fullHydrateCounter = RequestCounter()
    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)

        if url.path == "/identity" {
            return try identityResponse(for: url)
        }

        if url.path == "/status/sessions", url.query == nil {
            fullHydrateCounter.increment()
            let metadata = fullHydrateCounter.value == 1
                ? []
                : [sessionJSON(sessionKey: "55", ratingKey: "901", state: "playing", viewOffset: 4000)]
            return try sessionsResponse(for: url, metadata: metadata)
        }

        throw URLError(.unsupportedURL)
    }

    let settings = makeSessionStoreSettings(defaults: defaults)
    let store = makeSessionStore(
        settings: settings,
        session: session,
        eventsClient: PlexSessionEventsClient { _, onEvent in
            try await onEvent(.connected)
            try await onEvent(.playing(PlexPlaySessionStateNotification(
                sessionKey: "55",
                state: "playing",
                viewOffset: 4000,
                ratingKey: "901",
                key: "/library/metadata/901",
                transcodeSessionKey: nil
            )))
            try await Task.sleep(for: .seconds(60))
        }
    )
    defer { stopSessionMonitoring(store: store, settings: settings) }

    await waitForSessionStore(store) { $0.activeStreamCount == 1 && $0.sessions.first?.canonicalSessionKey == "55" }

    #expect(fullHydrateCounter.value == 2)
}

@MainActor
@Test func stoppedPlayingEventRemovesSessionWithoutHttp() async throws {
    let suiteName = "PlexBarTests.stoppedPlayingEventRemovesSessionWithoutHttp"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let fullHydrateCounter = RequestCounter()
    let targetedHydrateCounter = RequestCounter()
    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)

        if url.path == "/identity" {
            return try identityResponse(for: url)
        }

        if url.path == "/status/sessions", url.query == nil {
            fullHydrateCounter.increment()
            return try sessionsResponse(for: url, metadata: [sessionJSON(sessionKey: "44", ratingKey: "900", state: "playing", viewOffset: 1000)])
        }

        if url.path == "/status/sessions", url.query?.contains("sessionKey=") == true {
            targetedHydrateCounter.increment()
            return try sessionsResponse(for: url, metadata: [])
        }

        throw URLError(.unsupportedURL)
    }

    let settings = makeSessionStoreSettings(defaults: defaults)
    let store = makeSessionStore(
        settings: settings,
        session: session,
        eventsClient: PlexSessionEventsClient { _, onEvent in
            try await onEvent(.connected)
            try await onEvent(.playing(PlexPlaySessionStateNotification(
                sessionKey: "44",
                state: "stopped",
                viewOffset: nil,
                ratingKey: "900",
                key: "/library/metadata/900",
                transcodeSessionKey: nil,
                hasViewOffset: false
            )))
            try await Task.sleep(for: .seconds(60))
        }
    )
    defer { stopSessionMonitoring(store: store, settings: settings) }

    await waitForSessionStore(store) { $0.activeStreamCount == 0 && $0.lastUpdated != nil }

    #expect(store.activitySummary.streamCount == 0)
    #expect(store.lastHydratedAt != nil)
    #expect(fullHydrateCounter.value == 1)
    #expect(targetedHydrateCounter.value == 0)
}

@MainActor
@Test func reconnectReplacesTheActiveSessionSet() async throws {
    let suiteName = "PlexBarTests.reconnectReplacesTheActiveSessionSet"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let fullHydrateCounter = RequestCounter()
    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)

        if url.path == "/identity" {
            return try identityResponse(for: url)
        }

        if url.path == "/status/sessions", url.query == nil {
            fullHydrateCounter.increment()

            let metadata: [String]
            switch fullHydrateCounter.value {
            case 1:
                metadata = [sessionJSON(sessionKey: "44", ratingKey: "900", state: "playing", viewOffset: 1000)]
            default:
                metadata = [sessionJSON(sessionKey: "55", ratingKey: "901", state: "playing", viewOffset: 4000)]
            }

            return try sessionsResponse(for: url, metadata: metadata)
        }

        throw URLError(.unsupportedURL)
    }

    let settings = makeSessionStoreSettings(defaults: defaults)
    let store = makeSessionStore(
        settings: settings,
        session: session,
        eventsClient: PlexSessionEventsClient { _, onEvent in
            try await onEvent(.connected)
            try await onEvent(.connected)
            try await Task.sleep(for: .seconds(60))
        }
    )
    defer { stopSessionMonitoring(store: store, settings: settings) }

    await waitForSessionStore(store) {
        $0.activeStreamCount == 1 &&
        $0.sessions.first?.canonicalSessionKey == "55" &&
        $0.sessions.contains(where: { $0.canonicalSessionKey == "44" }) == false
    }

    #expect(fullHydrateCounter.value == 2)
}

@MainActor
@Test func heartbeatFailureReconnectsAndRehydratesActiveSessions() async throws {
    let suiteName = "PlexBarTests.heartbeatFailureReconnectsAndRehydratesActiveSessions"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let fullHydrateCounter = RequestCounter()
    let monitorStartCounter = RequestCounter()
    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)

        if url.path == "/identity" {
            return try identityResponse(for: url)
        }

        if url.path == "/status/sessions", url.query == nil {
            fullHydrateCounter.increment()

            let metadata: [String]
            switch fullHydrateCounter.value {
            case 1:
                metadata = [sessionJSON(sessionKey: "44", ratingKey: "900", state: "playing", viewOffset: 1000)]
            default:
                metadata = [sessionJSON(sessionKey: "55", ratingKey: "901", state: "playing", viewOffset: 4000)]
            }

            return try sessionsResponse(for: url, metadata: metadata)
        }

        throw URLError(.unsupportedURL)
    }

    let settings = makeSessionStoreSettings(defaults: defaults)
    let store = makeSessionStore(
        settings: settings,
        session: session,
        eventsClient: PlexSessionEventsClient { _, onEvent in
            monitorStartCounter.increment()
            try await onEvent(.connected)

            if monitorStartCounter.value == 1 {
                throw PlexSessionEventsError.heartbeatTimedOut
            }

            try await Task.sleep(for: .seconds(60))
        }
    )
    defer { stopSessionMonitoring(store: store, settings: settings) }

    await waitForSessionStore(store, timeoutNanoseconds: 4_000_000_000) {
        $0.activeStreamCount == 1 &&
        $0.sessions.first?.canonicalSessionKey == "55" &&
        $0.sessions.contains(where: { $0.canonicalSessionKey == "44" }) == false
    }

    #expect(monitorStartCounter.value >= 2)
    #expect(fullHydrateCounter.value == 2)
}

@MainActor
@Test func transcodeIdentityChangeRefreshesTheActiveSessionList() async throws {
    let suiteName = "PlexBarTests.transcodeIdentityChangeRefreshesTheActiveSessionList"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let fullHydrateCounter = RequestCounter()
    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)

        if url.path == "/identity" {
            return try identityResponse(for: url)
        }

        if url.path == "/status/sessions", url.query == nil {
            fullHydrateCounter.increment()
            let metadata = fullHydrateCounter.value == 1
                ? [
                    sessionJSON(sessionKey: "44", ratingKey: "900", state: "playing", viewOffset: 1000),
                    sessionJSON(sessionKey: "55", ratingKey: "901", state: "playing", viewOffset: 1000)
                ]
                : [sessionJSON(
                    sessionKey: "44", ratingKey: "900", state: "playing", viewOffset: 1000,
                    transcodeSessionKey: "/transcode/sessions/abc"
                )]
            return try sessionsResponse(for: url, metadata: metadata)
        }

        throw URLError(.unsupportedURL)
    }

    let settings = makeSessionStoreSettings(defaults: defaults)
    let store = makeSessionStore(
        settings: settings,
        session: session,
        eventsClient: PlexSessionEventsClient { _, onEvent in
            try await onEvent(.connected)
            try await onEvent(.playing(PlexPlaySessionStateNotification(
                sessionKey: "44",
                state: "playing",
                viewOffset: 1500,
                ratingKey: "900",
                key: "/library/metadata/900",
                transcodeSessionKey: "/transcode/sessions/abc"
            )))
            try await Task.sleep(for: .seconds(60))
        }
    )
    defer { stopSessionMonitoring(store: store, settings: settings) }

    await waitForSessionStore(store) {
        $0.sessions.first?.canonicalSessionKey == "44" &&
        $0.sessions.first?.transcodeSessionKey == "/transcode/sessions/abc"
    }

    #expect(fullHydrateCounter.value == 2)
    #expect(store.sessions.map(\.canonicalSessionKey) == ["44"])
}

@MainActor
@Test func connectionRecheckPromotesRemoteConnectionBackToLocal() async throws {
    let suiteName = "PlexBarTests.connectionRecheckPromotesRemoteConnectionBackToLocal"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let monitorURLs = Locked<[URL]>([])
    let recheckSleeps = RequestCounter()
    let remoteURL = try #require(URL(string: "https://plex.remote:32400"))
    let localURL = try #require(URL(string: "https://plex.local:32400"))
    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)

        if url.path == "/identity" {
            return try identityResponse(for: url)
        }

        if url.path == "/status/sessions", url.host == "plex.remote" {
            return try sessionsResponse(for: url, metadata: [
                sessionJSON(sessionKey: "44", ratingKey: "900", state: "playing", viewOffset: 1000)
            ])
        }

        if url.path == "/status/sessions", url.host == "plex.local" {
            return try sessionsResponse(for: url, metadata: [
                sessionJSON(sessionKey: "55", ratingKey: "901", state: "playing", viewOffset: 2000)
            ])
        }

        throw URLError(.unsupportedURL)
    }

    let remoteOnlyServer = PlexServerResource(
        id: "server-id",
        name: "Server",
        productVersion: nil,
        accessToken: "server-token",
        connections: [
            PlexServerConnection(uri: remoteURL, local: false, relay: false)
        ]
    )

    let upgradedServer = PlexServerResource(
        id: "server-id",
        name: "Server",
        productVersion: nil,
        accessToken: "server-token",
        connections: [
            PlexServerConnection(uri: localURL, local: true, relay: false),
            PlexServerConnection(uri: remoteURL, local: false, relay: false)
        ]
    )

    let settings = makeSessionStoreSettings(defaults: defaults)
    settings.connectionRecheckIntervalSeconds = 900

    let resolver = PlexConnectionResolver(
        client: PlexAPIClient(session: session),
        probeTimeoutInterval: 0.1
    )
    let connectionStore = PlexConnectionStore(
        settings: settings,
        resolver: resolver
    )
    let store = PlexSessionStore(
        connectionStore: connectionStore,
        client: PlexAPIClient(session: session),
        eventsClient: PlexSessionEventsClient { configuration, onEvent in
            monitorURLs.withValue { $0.append(configuration.serverURL) }
            try await onEvent(.connected)
            try await Task.sleep(for: .seconds(60))
        },
        connectionRecheckSleep: { _ in
            recheckSleeps.increment()
            if recheckSleeps.value == 1 {
                while monitorURLs.value != [remoteURL] {
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                await MainActor.run {
                    connectionStore.updateAvailableServers([upgradedServer])
                }
                return
            }

            throw CancellationError()
        }
    )
    defer { stopSessionMonitoring(store: store, settings: settings) }

    connectionStore.updateAvailableServers([remoteOnlyServer])
    store.didChangeConfiguration()

    await waitForSessionStore(store) {
        $0.sessions.first?.canonicalSessionKey == "55"
    }

    let seenURLs = monitorURLs.value
    #expect(seenURLs == [remoteURL, localURL])
}

@MainActor
@Test func startupPrefersLocalConnectionOverCachedRemoteWhenServerInventoryIsAvailable() async throws {
    let suiteName = "PlexBarTests.startupPrefersLocalConnectionOverCachedRemoteWhenServerInventoryIsAvailable"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let monitorURLs = Locked<[URL]>([])
    let remoteURL = try #require(URL(string: "https://plex.remote:32400"))
    let localURL = try #require(URL(string: "https://plex.local:32400"))
    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)

        if url.path == "/identity" {
            return try identityResponse(for: url)
        }

        if url.path == "/status/sessions", url.host == "plex.local" {
            return try sessionsResponse(for: url, metadata: [
                sessionJSON(sessionKey: "55", ratingKey: "901", state: "playing", viewOffset: 2000)
            ])
        }

        if url.path == "/status/sessions", url.host == "plex.remote" {
            Issue.record("Startup should not hydrate sessions from the cached remote connection when local is available.")
            return try sessionsResponse(for: url, metadata: [])
        }

        throw URLError(.unsupportedURL)
    }

    let server = PlexServerResource(
        id: "server-id",
        name: "Server",
        productVersion: nil,
        accessToken: "server-token",
        connections: [
            PlexServerConnection(uri: localURL, local: true, relay: false),
            PlexServerConnection(uri: remoteURL, local: false, relay: false)
        ]
    )

    let settings = makeSessionStoreSettings(defaults: defaults)
    settings.cachedConnectionURLString = remoteURL.absoluteString
    settings.cachedConnectionKind = .remote
    settings.connectionRecheckIntervalSeconds = 0

    let store = makeSessionStore(
        settings: settings,
        session: session,
        eventsClient: PlexSessionEventsClient { configuration, onEvent in
            monitorURLs.withValue { $0.append(configuration.serverURL) }
            try await onEvent(.connected)
            try await Task.sleep(for: .seconds(60))
        },
        availableServers: [server]
    )
    defer { stopSessionMonitoring(store: store, settings: settings) }

    await waitForSessionStore(store) {
        $0.sessions.first?.canonicalSessionKey == "55"
    }

    let seenURLs = monitorURLs.value
    #expect(seenURLs == [localURL])
}


@MainActor
@Test func activitySummaryClearsImmediatelyWhenServerChanges() async throws {
    let defaults = try #require(UserDefaults(suiteName: "PlexBarTests.activitySummaryServerChange"))
    defaults.removePersistentDomain(forName: "PlexBarTests.activitySummaryServerChange")
    defer { defaults.removePersistentDomain(forName: "PlexBarTests.activitySummaryServerChange") }
    let session = makeSessionStoreMockSession { request in
        let url = try #require(request.url)
        if url.path == "/identity" { return try identityResponse(for: url) }
        return try sessionsResponse(for: url, metadata: [sessionJSON(sessionKey: "44", ratingKey: "900", state: "playing", viewOffset: 1000)])
    }
    let settings = makeSessionStoreSettings(defaults: defaults)
    let store = makeSessionStore(settings: settings, session: session, eventsClient: PlexSessionEventsClient { _, onEvent in
        try await onEvent(.connected)
        try await Task.sleep(for: .seconds(60))
    })
    defer { stopSessionMonitoring(store: store, settings: settings) }
    #expect(store.lastHydratedAt == nil)
    await waitForSessionStore(store) { $0.activeStreamCount == 1 }
    #expect(store.lastHydratedAt != nil)
    settings.selectedServerIdentifier = "another-server"
    store.didChangeConfiguration()
    #expect(store.activitySummary.streamCount == 0)
    #expect(store.lastHydratedAt == nil)
    #expect(store.activityErrorMessage == nil)
}

}

@MainActor
private func waitForSessionStore(
    _ store: PlexSessionStore,
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    condition: @escaping @MainActor (PlexSessionStore) -> Bool
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while DispatchTime.now().uptimeNanoseconds < deadline {
        if condition(store) {
            return
        }

        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while DispatchTime.now().uptimeNanoseconds < deadline {
        if condition() {
            return
        }

        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

@MainActor
private func makeSessionStore(
    settings: PlexSettingsStore,
    session: URLSession,
    geoIPClient: PlexGeoIPClient = PlexGeoIPClient(),
    eventsClient: PlexSessionEventsClient,
    availableServers: [PlexServerResource] = [],
    connectionRecheckSleep: @escaping PlexSessionStore.ConnectionRecheckSleep = { duration in
        try await Task.sleep(for: duration)
    },
    activityClock: PlexActivityRefreshClock = .continuous
) -> PlexSessionStore {
    let resolver = PlexConnectionResolver(
        client: PlexAPIClient(session: session),
        probeTimeoutInterval: 0.1
    )
    let connectionStore = PlexConnectionStore(
        settings: settings,
        resolver: resolver
    )
    let effectiveServers: [PlexServerResource]
    if !availableServers.isEmpty {
        effectiveServers = availableServers
    } else if let cachedURL = settings.normalizedServerURL,
              let selectedServerIdentifier = settings.selectedServerIdentifier,
              let selectedServerName = settings.selectedServerName?.nilIfBlank ?? settings.selectedServerIdentifier {
        effectiveServers = [
            PlexServerResource(
                id: selectedServerIdentifier,
                name: selectedServerName,
                productVersion: nil,
                accessToken: settings.trimmedServerToken,
                connections: [
                    PlexServerConnection(
                        uri: cachedURL,
                        local: settings.cachedConnectionKind != .remote && settings.cachedConnectionKind != .relay,
                        relay: settings.cachedConnectionKind == .relay
                    )
                ]
            )
        ]
    } else {
        effectiveServers = []
    }

    if !effectiveServers.isEmpty {
        connectionStore.updateAvailableServers(effectiveServers)
    }

    let store = PlexSessionStore(
        connectionStore: connectionStore,
        client: PlexAPIClient(session: session),
        geoIPClient: geoIPClient,
        eventsClient: eventsClient,
        connectionRecheckSleep: connectionRecheckSleep,
        activityClock: activityClock
    )

    store.didChangeConfiguration()

    return store
}

@MainActor
private func makeSessionStoreSettings(defaults: UserDefaults) -> PlexSettingsStore {
    let settings = PlexSettingsStore(
        defaults: defaults,
        keychain: KeychainStore(service: "tests.\(defaults)")
    )
    settings.selectedServerIdentifier = "server-id"
    settings.selectedServerName = "Server"
    settings.serverToken = "server-token"
    settings.cachedConnectionURLString = "http://plex.local:32400"
    settings.cachedConnectionKind = .local
    return settings
}

@MainActor
private func stopSessionMonitoring(store: PlexSessionStore, settings: PlexSettingsStore) {
    settings.clearAuthentication()
    store.didChangeConfiguration()
}

private func identityResponse(for url: URL) throws -> (HTTPURLResponse, Data) {
    let response = try #require(HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    ))
    let data = try #require(#"""
    {
      "MediaContainer": {
        "claimed": true,
        "machineIdentifier": "server-id",
        "version": "1.0.0"
      }
    }
    """#.data(using: .utf8))
    return (response, data)
}

private func sessionsResponse(for url: URL, metadata: [String]) throws -> (HTTPURLResponse, Data) {
    let response = try #require(HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    ))
    let joinedMetadata = metadata.joined(separator: ",")
    let data = try #require(#"{"MediaContainer":{"Metadata":[\#(joinedMetadata)]}}"#.data(using: .utf8))
    return (response, data)
}

private func sessionJSON(
    sessionKey: String,
    ratingKey: String,
    state: String,
    viewOffset: Int,
    includeSessionID: Bool = true,
    transcodeSessionKey: String? = nil,
    sessionLocation: String = "lan",
    playerAddress: String? = nil,
    remotePublicAddress: String? = nil,
    playerLocal: Bool? = nil,
    playerRelayed: Bool? = nil,
    type: String = "movie",
    title: String = "Heat"
) -> String {
    let sessionIDJSON = includeSessionID ? "\n        \"id\": \"\(sessionKey)\"," : ""
    let transcodeSessionJSON = transcodeSessionKey.map { key in
        ",\n      \"TranscodeSession\": {\n        \"key\": \"\(key)\"\n      }"
    } ?? ""
    let playerAddressJSON = playerAddress.map { ",\n        \"address\": \"\($0)\"" } ?? ""
    let remotePublicAddressJSON = remotePublicAddress.map { ",\n        \"remotePublicAddress\": \"\($0)\"" } ?? ""
    let playerLocalJSON = playerLocal.map { ",\n        \"local\": \($0)" } ?? ""
    let playerRelayedJSON = playerRelayed.map { ",\n        \"relayed\": \($0)" } ?? ""

    return #"""
    {
      "sessionKey": "\#(sessionKey)",
      "ratingKey": "\#(ratingKey)",
      "key": "/library/metadata/\#(ratingKey)",
      "type": "\#(type)",
      "title": "\#(title)",
      "viewOffset": \#(viewOffset),
      "Player": {
        "title": "Apple TV",
        "state": "\#(state)"\#(playerAddressJSON)\#(remotePublicAddressJSON)\#(playerLocalJSON)\#(playerRelayedJSON)
      },
      "Session": {
        \#(sessionIDJSON)
        "location": "\#(sessionLocation)"
      }\#(transcodeSessionJSON)
    }
    """#
}

private func trackSessionJSON(
    sessionKey: String,
    ratingKey: String,
    state: String,
    viewOffset: Int,
    streamID: Int
) -> String {
    #"""
    {
      "sessionKey": "\#(sessionKey)",
      "ratingKey": "\#(ratingKey)",
      "key": "/library/metadata/\#(ratingKey)",
      "type": "track",
      "title": "Siddhartha",
      "duration": 10000,
      "viewOffset": \#(viewOffset),
      "Player": {
        "title": "Prologue",
        "state": "\#(state)"
      },
      "Session": {
        "id": "\#(sessionKey)",
        "location": "wan"
      },
      "Media": [
        {
          "Part": [
            {
              "Stream": [
                {
                  "id": \#(streamID),
                  "streamType": 2,
                  "codec": "aac",
                  "selected": true
                }
              ]
            }
          ]
        }
      ]
    }
    """#
}

private func sessionJSONWithoutCanonicalKey(
    ratingKey: String,
    state: String,
    viewOffset: Int
) -> String {
    #"""
    {
      "ratingKey": "\#(ratingKey)",
      "key": "/library/metadata/\#(ratingKey)",
      "type": "movie",
      "title": "Heat",
      "viewOffset": \#(viewOffset),
      "Player": {
        "title": "Apple TV",
        "state": "\#(state)"
      }
    }
    """#
}

private func makeSessionStoreMockSession(
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    SessionStoreMockURLProtocol.requestHandler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SessionStoreMockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class SessionStoreMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func withValue(_ update: (inout Value) -> Void) {
        lock.lock()
        update(&storage)
        lock.unlock()
    }
}

@MainActor
private final class ActivityRefreshFixture {
    let clock = ActivityTestClock()
    let requests = RequestCounter()
    let bandwidth = Locked(8000)
    let invalidResponse = Locked(false)
    let handler = Locked<PlexSessionEventsClient.MonitorHandler?>(nil)
    let defaults: UserDefaults
    let suiteName: String
    let settings: PlexSettingsStore
    let store: PlexSessionStore

    init(empty: Bool = false, beforeResponse: @escaping @Sendable (Int) -> Void = { _ in }) throws {
        suiteName = "PlexBarTests.activityRefresh.\(UUID())"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        settings = makeSessionStoreSettings(defaults: defaults)
        let requests = requests, bandwidth = bandwidth, invalidResponse = invalidResponse, handler = handler
        let session = makeSessionStoreMockSession { request in
            let url = try #require(request.url)
            if url.path == "/identity" { return try identityResponse(for: url) }
            #expect(url.path == "/status/sessions")
            requests.increment()
            let metadata = sessionJSON(sessionKey: "44", ratingKey: "900", state: "paused", viewOffset: 1000)
                .replacingOccurrences(of: "\"location\":", with: "\"bandwidth\": \(bandwidth.value), \"location\":")
            beforeResponse(requests.value)
            if invalidResponse.value {
                let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
                return (response, Data("invalid JSON".utf8))
            }
            return try sessionsResponse(for: url, metadata: empty ? [] : [metadata])
        }
        store = makeSessionStore(
            settings: settings, session: session,
            eventsClient: PlexSessionEventsClient { _, onEvent in
                try await onEvent(.connected)
                handler.withValue { $0 = onEvent }
                try await Task.sleep(for: .seconds(60))
            },
            activityClock: clock.clock
        )
    }

    func ready() async {
        await waitUntil { self.handler.value != nil && self.store.lastHydratedAt != nil }
        #expect(store.lastHydratedAt != nil)
        #expect(requests.value == 1)
    }

    func stop() {
        stopSessionMonitoring(store: store, settings: settings)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private final class ActivityTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant = ContinuousClock.now
    private var waiters: [UUID: (ContinuousClock.Instant, CheckedContinuation<Void, Error>)] = [:]

    var clock: PlexActivityRefreshClock {
        PlexActivityRefreshClock(now: { self.now }, sleepUntil: { try await self.sleep(until: $0) })
    }

    var now: ContinuousClock.Instant {
        lock.lock()
        defer { lock.unlock() }
        return instant
    }

    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return waiters.count
    }

    func advance(by duration: Duration) {
        lock.lock()
        instant += duration
        let ready = waiters.filter { $0.value.0 <= instant }
        for id in ready.keys { waiters.removeValue(forKey: id) }
        lock.unlock()
        for waiter in ready.values { waiter.1.resume() }
    }

    private func sleep(until deadline: ContinuousClock.Instant) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if Task.isCancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                } else if deadline <= instant {
                    lock.unlock()
                    continuation.resume()
                } else {
                    waiters[id] = (deadline, continuation)
                    lock.unlock()
                }
            }
        } onCancel: {
            self.lock.lock()
            let waiter = self.waiters.removeValue(forKey: id)
            self.lock.unlock()
            waiter?.1.resume(throwing: CancellationError())
        }
    }
}

@MainActor
private final class ActivityVisibilityTestWindow: NSWindow {
    private var reportedVisible = false
    override var isVisible: Bool { reportedVisible }
    override var occlusionState: NSWindow.OcclusionState { reportedVisible ? [.visible] : [] }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                   styleMask: .borderless, backing: .buffered, defer: true)
    }

    func setVisible(_ visible: Bool) {
        reportedVisible = visible
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: self)
    }
}
