import PlexModels
import Foundation
import Testing
@testable import PlexBar

struct PlexActivitySummaryTests {
    @Test func mockServerExercisesAllKnownDeliveryMethods() async throws {
        let client = PlexAPIClient(session: PlexDebugMockServer.makeSession())
        let sessions = try await client.fetchSessions(using: PlexConnectionConfiguration(
            serverURL: PlexDebugMockServer.mockResolvedConnection.url,
            token: "plexbar-debug-mock-server-token",
            clientContext: PlexClientContext(clientIdentifier: "activity-tests")
        ))
        let summary = PlexActivitySummary(sessions: sessions)
        #expect(summary.streamCount == 4)
        #expect(summary.directPlayCount == 2)
        #expect(summary.directStreamCount == 1)
        #expect(summary.transcodingCount == 1)
        #expect(summary.unknownCount == 0)
        #expect(summary.totalBandwidthKbps == 30920)
    }

    @Test func mixedSessionsCountOnceAndSumReportedBandwidth() throws {
        let sessions = try [
            decodeSession(part: #"{"decision":"directplay"}"#, bandwidth: 13900, location: "wan"),
            decodeSession(part: #"{"decision":"transcode","Stream":[{"streamType":1,"decision":"transcode"},{"streamType":2,"selected":true,"decision":"transcode"}]}"#, bandwidth: 21300, location: "wan"),
            decodeSession(part: #"{"decision":"transcode","Stream":[{"streamType":1,"decision":"copy"},{"streamType":2,"selected":true,"decision":"transcode"}]}"#, bandwidth: 9500, location: "lan", state: "paused")
        ]
        let summary = PlexActivitySummary(sessions: sessions)
        #expect(summary.streamCount == 3)
        #expect(summary.directPlayCount == 1)
        #expect(summary.transcodingCount == 2)
        #expect(summary.directStreamCount == 0)
        #expect(summary.unknownCount == 0)
        #expect(summary.totalBandwidthKbps == 44700)
        #expect(summary.localBandwidthKbps == 9500)
        #expect(summary.remoteBandwidthKbps == 35200)
        #expect(!summary.hasPartialBandwidth)
    }

    @Test(arguments: [
        (#"{"decision":"transcode","Stream":[{"streamType":1,"decision":"copy"},{"streamType":2,"decision":"copy"}]}"#, PlexSessionDeliveryMethod.directStream),
        (#"{"decision":"transcode","Stream":[{"streamType":2,"decision":"copy"}]}"#, .directStream),
        (#"{"decision":"transcode","Stream":[{"streamType":2,"decision":"transcode"}]}"#, .transcoding),
        (#"{"decision":"transcode","Stream":[{"streamType":1,"decision":"transcode"},{"streamType":3,"selected":true,"decision":"burn"}]}"#, .transcoding),
        (#"{"decision":"transcode","Stream":[{"streamType":1,"decision":"copy"},{"streamType":3,"selected":true,"decision":"transcode"}]}"#, .directStream),
        (#"{"decision":"transcode"}"#, .unknown),
        (#"{"decision":"transcode","Stream":[{"streamType":1,"decision":"copy"},{"streamType":2}]}"#, .directStream),
        (#"{"decision":"future-value"}"#, .unknown),
        (#"{}"#, .unknown),
        (#"{"Stream":[{"streamType":1},{"streamType":2,"selected":true}]}"#, .directPlay),
        (#"{"Stream":[{"streamType":2,"decision":""}]}"#, .directPlay),
        (#"{"Stream":[{"streamType":1,"decision":"copy"}]}"#, .directStream),
        (#"{"Stream":[{"streamType":2,"decision":"transcode"}]}"#, .transcoding),
        (#"{"Stream":[{"streamType":2,"decision":"future-value"}]}"#, .unknown),
        (#"{"decision":"transcode","Stream":[{"streamType":2}]}"#, .unknown)
    ])
    func classifiesOnlyEstablishedDecisions(part: String, expected: PlexSessionDeliveryMethod) throws {
        #expect(try decodeSession(part: part).deliveryMethod == expected)
    }

    @Test func ignoresUnselectedAlternativesAndInactiveSubtitles() throws {
        let session = try decodeSession(part: #"""
        {"decision":"transcode","Stream":[
            {"streamType":1,"decision":"copy"},
            {"streamType":2,"selected":false,"decision":"transcode"},
            {"streamType":2,"selected":true,"decision":"copy"},
            {"streamType":3,"selected":false,"decision":"burn"},
            {"streamType":3,"decision":"ignore"}
        ]}
        """#)
        #expect(session.deliveryMethod == .directStream)
    }

    @Test func selectionFlagsDecodeAndChooseActiveMediaAndPart() throws {
        let json = #"""
        {"title":"Example","Player":{},"Media":[
            {"selected":0,"Part":[{"decision":"directplay"}]},
            {"selected":"1","Part":[
                {"selected":false,"decision":"directplay"},
                {"selected":1,"decision":"transcode","Stream":[
                    {"streamType":2,"selected":"1","decision":"transcode"}
                ]}
            ]}
        ]}
        """#
        let session = try JSONDecoder().decode(PlexSession.self, from: Data(json.utf8))
        #expect(session.media?.last?.selected == true)
        #expect(session.media?.last?.part?.last?.selected == true)
        #expect(session.deliveryMethod == .transcoding)
    }

    @Test(arguments: [
        #"[{"Part":[{"decision":"directplay"}]},{"Part":[{"decision":"transcode"}]}]"#,
        #"[{"Part":[{"decision":"directplay"},{"decision":"transcode"}]}]"#,
        #"[{"selected":true,"Part":[]},{"selected":true,"Part":[]}]"#,
        #"[{"Part":[{"decision":"transcode","Stream":[{"streamType":2,"decision":"copy"},{"streamType":2,"decision":"transcode"}]}]}]"#
    ])
    func ambiguousSelectionIsUnknown(media: String) throws {
        let json = "{\"title\":\"Example\",\"Player\":{},\"Media\":\(media)}"
        let session = try JSONDecoder().decode(PlexSession.self, from: Data(json.utf8))
        #expect(session.deliveryMethod == .unknown)
    }

    @Test func directPlayPartDoesNotRequireSourceTrackSelection() throws {
        // Source tracks are not playback decisions; clients can choose among them locally.
        let session = try decodeSession(part: #"""
        {"decision":"directplay","Stream":[
            {"streamType":1},
            {"streamType":2}, {"streamType":2},
            {"streamType":3,"decision":"copy"}, {"streamType":3,"decision":"copy"}
        ]}
        """#)
        #expect(session.deliveryMethod == .directPlay)
    }

    @Test(arguments: [
        (#"{"videoDecision":"transcode","audioDecision":"copy"}"#, PlexSessionDeliveryMethod.transcoding),
        (#"{"videoDecision":"copy","audioDecision":"transcode"}"#, .transcoding),
        (#"{"videoDecision":"copy","audioDecision":"copy"}"#, .directStream),
        (#"{"audioDecision":"transcode"}"#, .transcoding),
        (#"{"key":"/transcode/sessions/example"}"#, .unknown)
    ])
    func liveTVUsesTranscodeOutputDecisions(transcode: String, expected: PlexSessionDeliveryMethod) throws {
        let json = """
        {"title":"Live TV","live":true,"Player":{},
         "Media":[{"Part":[{"decision":"directplay","Stream":[{"streamType":1}]}]}],
         "TranscodeSession":\(transcode)}
        """
        let session = try JSONDecoder().decode(PlexSession.self, from: Data(json.utf8))
        #expect(session.deliveryMethod == expected)
    }

    @Test func playbackNotificationPreservesDecisionsOnlyForTheSameTranscode() throws {
        let json = #"""
        {"title":"Live TV","live":true,"Player":{},"TranscodeSession":{
          "key":"/transcode/sessions/example","videoDecision":"copy","audioDecision":"transcode"
        }}
        """#
        let session = try JSONDecoder().decode(PlexSession.self, from: Data(json.utf8))
        for key in ["/transcode/sessions/example", "/transcode/sessions/replacement"] {
            let updated = session.applying(playNotification: PlexPlaySessionStateNotification(
                sessionKey: nil, state: "paused", viewOffset: 1234, ratingKey: nil, key: nil,
                transcodeSessionKey: key, hasRatingKey: false, hasKey: false
            ))
            #expect(updated.deliveryMethod == (key == session.transcodeSessionKey ? .transcoding : .unknown))
        }
    }

    @Test func classifiesCapturedPlexSessions() throws {
        // Actual /status/sessions decision fields, captured September 12, 2026.
        // Titles are anonymous; credentials, addresses and media identifiers are omitted.
        let json = #"""
        [
          {"type":"movie","Media":[{"selected":true,"Part":[{"decision":"directplay","selected":true,"Stream":[{"streamType":1},{"selected":true,"streamType":2}]}]}],"title":"Session 1","Player":{}},
          {"type":"episode","Media":[{"selected":true,"Part":[{"decision":"directplay","selected":true,"Stream":[{"streamType":1},{"selected":true,"streamType":2}]}]}],"title":"Session 2","Player":{}},
          {"type":"episode","Media":[{"selected":true,"Part":[{"decision":"transcode","selected":true,"Stream":[{"streamType":1,"decision":"transcode"},{"selected":true,"streamType":2,"decision":"transcode"},{"selected":true,"streamType":3,"decision":"transcode"}]}]}],"TranscodeSession":{"videoDecision":"transcode","audioDecision":"transcode"},"title":"Session 3","Player":{}},
          {"type":"episode","Media":[{"selected":true,"Part":[{"decision":"transcode","selected":true,"Stream":[{"streamType":1,"decision":"copy"},{"selected":true,"streamType":2,"decision":"transcode"}]}]}],"TranscodeSession":{"videoDecision":"copy","audioDecision":"transcode"},"title":"Session 4","Player":{}}
        ]
        """#
        let sessions = try JSONDecoder().decode([PlexSession].self, from: Data(json.utf8))
        let summary = PlexActivitySummary(sessions: sessions)
        #expect(summary.streamCount == 4)
        #expect(summary.directPlayCount == 2)
        #expect(summary.transcodingCount == 2)
        #expect(summary.directStreamCount == 0)
        #expect(summary.unknownCount == 0)
    }

    @Test func missingAndInvalidBandwidthAreNotZeroReports() throws {
        let summary = try PlexActivitySummary(sessions: [
            decodeSession(bandwidth: 100, location: "lan"),
            decodeSession(bandwidth: 200, location: "wan"),
            decodeSession(bandwidth: 300, location: "future"),
            decodeSession(bandwidth: 0, location: "lan"),
            decodeSession(bandwidth: -1),
            decodeSession()
        ])
        #expect(summary.streamCount == 6)
        #expect(summary.reportedBandwidthCount == 4)
        #expect(summary.totalBandwidthKbps == 600)
        #expect(summary.unknownLocationBandwidthKbps == 300)
        #expect(summary.unknownLocationCount == 1)
        #expect(summary.hasPartialBandwidth)
        #expect(summary.localBandwidthKbps + summary.remoteBandwidthKbps + summary.unknownLocationBandwidthKbps == summary.totalBandwidthKbps)
    }

    @Test func emptyAndUnavailableSummariesRemainDistinct() throws {
        let empty = PlexActivitySummary(sessions: [])
        let unavailable = try PlexActivitySummary(sessions: [decodeSession()])
        #expect(empty.streamCount == 0)
        #expect(unavailable.streamCount == 1)
        #expect(unavailable.reportedBandwidthCount == 0)
        #expect(!unavailable.hasPartialBandwidth)
    }

    @Test(arguments: [(44700.0, "44.7 Mbps"), (1000, "1 Mbps"), (0, "0 Mbps"), (1, "<0.1 Mbps"), (50, "0.1 Mbps")])
    func formatsDecimalBandwidth(kbps: Double, expected: String) {
        #expect(PlexActivitySummary.bandwidthText(kbps: kbps, locale: Locale(identifier: "en_US")) == expected)
    }

    @Test func formatsBandwidthForLocale() {
        #expect(PlexActivitySummary.bandwidthText(kbps: 44700, locale: Locale(identifier: "de_DE")) == "44,7 Mbps")
    }

    private func decodeSession(part: String = #"{"decision":"directplay"}"#, bandwidth: Int? = nil, location: String? = nil, state: String = "playing") throws -> PlexSession {
        var playback: [String: Any] = [:]
        playback["bandwidth"] = bandwidth
        playback["location"] = location
        let sessionObject = try JSONSerialization.jsonObject(with: Data(part.utf8))
        let json: [String: Any] = [
            "title": "Example", "Player": ["state": state], "Session": playback,
            "Media": [["Part": [sessionObject]]]
        ]
        return try JSONDecoder().decode(PlexSession.self, from: JSONSerialization.data(withJSONObject: json))
    }
}
