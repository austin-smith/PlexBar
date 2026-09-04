import Foundation
import Testing
@testable import PlexBar

private final class PlexBarTestsBundleToken {}

extension PlexMediaRequestTests {
    @Test func directPlayFixtureSelectsTheExactServerPart() async throws {
        let fixture = try playbackFixture("playback-decision-direct-play")
        let item = try playbackFixtureItem(from: fixture)
        let session = makeMediaMockSession { request in
            (try Self.successResponse(for: request), fixture)
        }

        let plan = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try fixtureConfiguration,
            capabilities: fixtureCapabilities
        )

        #expect(plan.method == .directPlay)
        #expect(plan.mediaKind == .video)
        #expect(plan.ratingKey == "42001")
        #expect(plan.startTime == 12)
        #expect(plan.duration == 634.533)
        #expect(plan.url.path == "/library/parts/71001/fixture.mp4")
        let queryItems = try #require(
            URLComponents(url: plan.url, resolvingAgainstBaseURL: false)?.queryItems
        )
        #expect(queryItems.contains { $0.name == "X-Plex-Token" && $0.value == "server-token" })
        #expect(queryItems.contains {
            $0.name == "X-Plex-Session-Identifier" && $0.value == plan.sessionIdentifier
        })
    }

    @Test func directStreamFixtureUsesTheAuthenticatedHLSStartContract() async throws {
        let fixture = try playbackFixture("playback-decision-direct-stream")
        let item = try playbackFixtureItem(from: fixture)
        let session = makeMediaMockSession { request in
            (try Self.successResponse(for: request), fixture)
        }

        let plan = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try fixtureConfiguration,
            capabilities: fixtureCapabilities
        )

        #expect(plan.method == .directStream)
        #expect(plan.url.path == "/video/:/transcode/universal/start.m3u8")
        let queryItems = try #require(
            URLComponents(url: plan.url, resolvingAgainstBaseURL: false)?.queryItems
        )
        #expect(queryItems.contains { $0.name == "protocol" && $0.value == "hls" })
        #expect(queryItems.contains { $0.name == "X-Plex-Token" && $0.value == "server-token" })
        #expect(queryItems.contains { $0.name == "X-Plex-Client-Profile-Name" && $0.value == "generic" })
    }

    @Test func publishedTranscodeFixtureSelectsTranscodeAndPreservesSessionContext() async throws {
        let fixture = try playbackFixture("playback-decision-transcode")
        let item = try playbackFixtureItem(from: fixture)
        let session = makeMediaMockSession { request in
            (try Self.successResponse(for: request), fixture)
        }

        let plan = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try fixtureConfiguration,
            capabilities: fixtureCapabilities
        )

        #expect(plan.method == .transcode)
        #expect(plan.ratingKey == "151671")
        #expect(plan.url.path == "/video/:/transcode/universal/start.m3u8")
        let queryItems = try #require(
            URLComponents(url: plan.url, resolvingAgainstBaseURL: false)?.queryItems
        )
        #expect(queryItems.contains { $0.name == "session" && $0.value == plan.sessionIdentifier })
        #expect(queryItems.contains {
            $0.name == "X-Plex-Session-Identifier" && $0.value == plan.sessionIdentifier
        })
    }

    @Test func musicTranscodeFixtureUsesPublishedMusicDecisionAndHLSStartContract() async throws {
        let fixture = try playbackFixture("playback-decision-music-transcode")
        let item = try playbackFixtureItem(from: fixture)
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            return (try Self.successResponse(for: request), fixture)
        }

        let plan = try await PlexAPIClient(session: session).makePlaybackPlan(
            for: item,
            using: try fixtureConfiguration,
            capabilities: fixtureCapabilities
        )

        let decisionRequest = try #require(capture.request)
        #expect(decisionRequest.url?.path == "/music/:/transcode/universal/decision")
        #expect(plan.method == .transcode)
        #expect(plan.mediaKind == .music)
        #expect(plan.url.path == "/music/:/transcode/universal/start.m3u8")
        let queryItems = try #require(
            URLComponents(url: plan.url, resolvingAgainstBaseURL: false)?.queryItems
        )
        let profile = try #require(
            queryItems.first(where: { $0.name == "X-Plex-Client-Profile-Extra" })?.value
        )
        #expect(profile.contains("type=musicProfile"))
        #expect(profile.contains("protocol=hls"))
        #expect(!profile.contains("type=videoProfile"))
        #expect(queryItems.contains { $0.name == "musicBitrate" && $0.value == "921" })
    }

    @Test func rejectedDecisionFixtureSurfacesTheServerReason() async throws {
        let sourceFixture = try playbackFixture("playback-decision-direct-play")
        let rejectedFixture = try playbackFixture("playback-decision-rejected")
        let item = try playbackFixtureItem(from: sourceFixture)
        let session = makeMediaMockSession { request in
            (try Self.successResponse(for: request), rejectedFixture)
        }

        do {
            _ = try await PlexAPIClient(session: session).makePlaybackPlan(
                for: item,
                using: try fixtureConfiguration,
                capabilities: fixtureCapabilities
            )
            Issue.record("Expected PMS to reject playback")
        } catch let PlexAPIError.playbackRejected(reason) {
            #expect(reason == "Playback is not possible for this item.")
        } catch {
            Issue.record("Unexpected playback error: \(error)")
        }
    }

    @Test func timelineFixturesCoverStateChangesSeekProgressAndCompletion() async throws {
        let fixture = try playbackFixture("timeline-normal")
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            return (try Self.successResponse(for: request), fixture)
        }
        let client = PlexAPIClient(session: session)
        let updates: [(PlexTimelineState, Int, Bool?)] = [
            (.buffering, 0, nil),
            (.playing, 1_000, nil),
            (.paused, 12_000, nil),
            (.playing, 18_000, nil),
            (.stopped, 60_000, false),
        ]

        for (state, time, continuing) in updates {
            let response = try await client.reportTimeline(
                PlexTimelineUpdate(
                    ratingKey: "42001",
                    state: state,
                    time: time,
                    duration: 60_000,
                    sessionIdentifier: "session-123",
                    playQueueItemID: "queue-item-9",
                    continuing: continuing
                ),
                endpointPath: "/provider/timeline",
                using: try fixtureConfiguration
            )

            #expect(response.termination == nil)
            let request = try #require(capture.request)
            let queryItems = try #require(
                URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            )
            #expect(queryItems.contains { $0.name == "state" && $0.value == state.rawValue })
            #expect(queryItems.contains { $0.name == "time" && $0.value == String(time) })
            #expect(queryItems.contains {
                $0.name == "playQueueItemID" && $0.value == "queue-item-9"
            })
            #expect(queryItems.contains { $0.name == "continuing" } == (state == .stopped))
        }
    }

    @Test func timelineTerminationFixtureDecodesTheAuthoritativeServerStop() async throws {
        let fixture = try playbackFixture("timeline-terminated")
        let session = makeMediaMockSession { request in
            (try Self.successResponse(for: request), fixture)
        }

        let response = try await PlexAPIClient(session: session).reportTimeline(
            PlexTimelineUpdate(
                ratingKey: "42001",
                state: .playing,
                time: 12_000,
                duration: 60_000,
                sessionIdentifier: "session-123"
            ),
            endpointPath: "/provider/timeline",
            using: try fixtureConfiguration
        )

        #expect(response.termination == PlexTimelineResponse.Termination(
            code: 2006,
            text: "Admin terminated playback with reason: Go Away"
        ))
        #expect(response.termination?.message == "Admin terminated playback with reason: Go Away")
    }

    @Test func continuingIsOmittedUntilTheTimelineStateIsStopped() async throws {
        let fixture = try playbackFixture("timeline-normal")
        let capture = RequestCapture()
        let session = makeMediaMockSession { request in
            capture.record(request)
            return (try Self.successResponse(for: request), fixture)
        }

        _ = try await PlexAPIClient(session: session).reportTimeline(
            PlexTimelineUpdate(
                ratingKey: "42001",
                state: .playing,
                time: 12_000,
                duration: 60_000,
                sessionIdentifier: "session-123",
                continuing: true
            ),
            endpointPath: "/provider/timeline",
            using: try fixtureConfiguration
        )

        let request = try #require(capture.request)
        let queryItems = try #require(
            URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
        )
        #expect(!queryItems.contains { $0.name == "continuing" })
    }

    private var fixtureConfiguration: PlexConnectionConfiguration {
        get throws {
            PlexConnectionConfiguration(
                serverURL: try #require(URL(string: "https://plex.local:32400")),
                token: "server-token",
                clientContext: PlexClientContext(clientIdentifier: "client-123")
            )
        }
    }

    private var fixtureCapabilities: PlexPlaybackCapabilities {
        PlexPlaybackCapabilities(
            directPlayContainers: ["mp4"],
            directPlayVideoCodecs: ["h264", "hevc"],
            directPlayAudioCodecs: ["aac", "opus"],
            directPlayMusicProfiles: [
                PlexMusicDirectPlayProfile(container: "mp3", audioCodec: "mp3"),
                PlexMusicDirectPlayProfile(container: "mp4", audioCodec: "aac"),
            ]
        )
    }

    private func playbackFixture(_ name: String) throws -> Data {
        let url = try #require(Bundle(for: PlexBarTestsBundleToken.self).url(
            forResource: name,
            withExtension: "json"
        ))
        return try Data(contentsOf: url)
    }

    private func playbackFixtureItem(from data: Data) throws -> PlexMediaItem {
        let decision = try JSONDecoder().decode(PlexPlaybackDecisionEnvelope.self, from: data)
        return try #require(decision.mediaContainer.metadata.first)
    }

    private static func successResponse(for request: URLRequest) throws -> HTTPURLResponse {
        try #require(HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
    }
}
