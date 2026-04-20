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

    #expect(fullHydrateCounter.value == 1)
    #expect(targetedHydrateCounter.value == 0)
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
@Test func unknownPlayingEventTriggersOneTargetedHydrate() async throws {
    let suiteName = "PlexBarTests.unknownPlayingEventTriggersOneTargetedHydrate"
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
            return try sessionsResponse(for: url, metadata: [])
        }

        if url.path == "/status/sessions", url.query?.contains("sessionKey=55") == true {
            targetedHydrateCounter.increment()
            return try sessionsResponse(for: url, metadata: [sessionJSON(sessionKey: "55", ratingKey: "901", state: "playing", viewOffset: 4000)])
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

    #expect(fullHydrateCounter.value == 1)
    #expect(targetedHydrateCounter.value == 1)
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
@Test func transcodeIdentityChangeTriggersOneTargetedHydrate() async throws {
    let suiteName = "PlexBarTests.transcodeIdentityChangeTriggersOneTargetedHydrate"
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
            return try sessionsResponse(for: url, metadata: [
                sessionJSON(sessionKey: "44", ratingKey: "900", state: "playing", viewOffset: 1000)
            ])
        }

        if url.path == "/status/sessions", url.query?.contains("sessionKey=44") == true {
            targetedHydrateCounter.increment()
            return try sessionsResponse(for: url, metadata: [
                sessionJSON(
                    sessionKey: "44",
                    ratingKey: "900",
                    state: "playing",
                    viewOffset: 1000,
                    transcodeSessionKey: "/transcode/sessions/abc"
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

    #expect(fullHydrateCounter.value == 1)
    #expect(targetedHydrateCounter.value == 1)
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
private func makeSessionStore(
    settings: PlexSettingsStore,
    session: URLSession,
    geoIPClient: PlexGeoIPClient = PlexGeoIPClient(),
    eventsClient: PlexSessionEventsClient,
    availableServers: [PlexServerResource] = [],
    connectionRecheckSleep: @escaping PlexSessionStore.ConnectionRecheckSleep = { duration in
        try await Task.sleep(for: duration)
    }
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
        connectionRecheckSleep: connectionRecheckSleep
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
    transcodeSessionKey: String? = nil,
    sessionLocation: String = "lan",
    playerAddress: String? = nil,
    remotePublicAddress: String? = nil,
    playerLocal: Bool? = nil,
    playerRelayed: Bool? = nil
) -> String {
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
      "type": "movie",
      "title": "Heat",
      "viewOffset": \#(viewOffset),
      "Player": {
        "title": "Apple TV",
        "state": "\#(state)"\#(playerAddressJSON)\#(remotePublicAddressJSON)\#(playerLocalJSON)\#(playerRelayedJSON)
      },
      "Session": {
        "id": "\#(sessionKey)",
        "location": "\#(sessionLocation)"
      }\#(transcodeSessionJSON)
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
