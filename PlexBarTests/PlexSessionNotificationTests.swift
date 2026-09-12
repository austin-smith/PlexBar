import Foundation
import Testing
@testable import PlexBar

@Test func decodesPlayingNotificationEvent() async throws {
    let data = try #require(#"""
    {
      "NotificationContainer": {
        "type": "playing",
        "PlaySessionStateNotification": [
          {
            "sessionKey": "44",
            "state": "playing",
            "viewOffset": 1234,
            "ratingKey": "900",
            "key": "/library/metadata/900",
            "transcodeSession": "abc"
          }
        ]
      }
    }
    """#.data(using: .utf8))

    let events = try PlexSessionEventsClient.decodeEvents(from: data)

    #expect(events == [
        .playing(PlexPlaySessionStateNotification(
            sessionKey: "44",
            state: "playing",
            viewOffset: 1234,
            ratingKey: "900",
            key: "/library/metadata/900",
            transcodeSessionKey: "/transcode/sessions/abc"
        ))
    ])
}

@Test(arguments: ["null", "\"\"", "\"   \""])
func emptyTranscodeReferenceClearsThePreviousTranscode(value: String) throws {
    let data = Data("""
    {"NotificationContainer":{"type":"playing","PlaySessionStateNotification":[
      {"sessionKey":"44","state":"playing","transcodeSession":\(value)}
    ]}}
    """.utf8)

    let event = try #require(PlexSessionEventsClient.decodeEvents(from: data).first)
    guard case .playing(let notification) = event else {
        Issue.record("Expected a playback notification")
        return
    }
    #expect(notification.hasTranscodeSession)
    #expect(notification.transcodeSessionKey == nil)
}

@Test func missingTranscodeReferenceDoesNotClearThePreviousTranscode() throws {
    let data = Data(#"{"NotificationContainer":{"type":"playing","PlaySessionStateNotification":[{"sessionKey":"44","state":"playing"}]}}"#.utf8)
    let event = try #require(PlexSessionEventsClient.decodeEvents(from: data).first)
    guard case .playing(let notification) = event else {
        Issue.record("Expected a playback notification")
        return
    }
    #expect(notification.hasTranscodeSession == false)
    #expect(notification.transcodeSessionKey == nil)
}

@Test func objectValuedTranscodeReferenceReportsTheFailingField() throws {
    let data = Data(#"{"NotificationContainer":{"type":"playing","PlaySessionStateNotification":[{"sessionKey":"44","state":"stopped","transcodeSession":{"key":"private-value"}}]}}"#.utf8)
    do {
        _ = try PlexSessionEventsClient.decodeEvents(from: data)
        Issue.record("Expected the invalid transcode field to fail decoding")
    } catch let error as DecodingError {
        let summary = PlexSessionEventsClient.decodingFailureSummary(error)
        #expect(summary.contains("type mismatch"))
        #expect(summary.contains("transcodeSession"))
        #expect(summary.contains("private-value") == false)
    }
}

@Test func decodingFailureSummaryExcludesPrivateErrorDetails() {
    let error = DecodingError.dataCorrupted(.init(
        codingPath: [],
        debugDescription: "Invalid credential: private-value"
    ))
    #expect(PlexSessionEventsClient.decodingFailureSummary(error) == "invalid data at root")
}

@Test func unrelatedServerNotificationsProduceNoSessionEvents() throws {
    let data = Data(#"{"NotificationContainer":{"type":"timeline","TimelineEntry":[{"state":5,"itemID":123}]}}"#.utf8)
    #expect(try PlexSessionEventsClient.decodeEvents(from: data).isEmpty)
}

@Test func decodesTranscodeSessionUpdateEvent() async throws {
    let data = try #require(#"""
    {
      "NotificationContainer": {
        "type": "transcodeSession.update",
        "TranscodeSession": [
          {
            "key": "/transcode/sessions/abc"
          }
        ]
      }
    }
    """#.data(using: .utf8))

    let events = try PlexSessionEventsClient.decodeEvents(from: data)

    #expect(events == [
        .transcodeSessionUpdate(PlexTranscodeSessionUpdate(key: "/transcode/sessions/abc"))
    ])
}

@Test func malformedNotificationPayloadProducesNoEvents() async throws {
    let data = try #require(#"""
    {
      "NotificationContainer": {
        "type": "playing",
        "PlaySessionStateNotification": [
          {
            "state": {
              "unexpected": true
            }
          }
        ]
      }
    }
    """#.data(using: .utf8))

    let events = PlexSessionEventsClient.decodeEventsIfPossible(from: data)

    #expect(events.isEmpty)
}

@Test func websocketHandshakeConfirmationCompletesAfterSuccessfulPing() async throws {
    try await PlexSessionEventsClient.confirmHandshake { completion in
        completion(nil)
    }
}

@Test func websocketHandshakeConfirmationThrowsPingFailure() async throws {
    let error = URLError(.cannotConnectToHost)

    do {
        try await PlexSessionEventsClient.confirmHandshake { completion in
            completion(error)
        }
        Issue.record("Expected ping failure to surface")
    } catch let receivedError as URLError {
        #expect(receivedError.code == .cannotConnectToHost)
    }
}

@Test func websocketHandshakeConfirmationTimesOutWhenPingNeverReturns() async throws {
    do {
        try await PlexSessionEventsClient.confirmHandshake(
            sendPing: { _ in },
            timeout: .milliseconds(10)
        )
        Issue.record("Expected handshake timeout to surface")
    } catch let error as PlexSessionEventsError {
        guard case .handshakeTimedOut = error else {
            Issue.record("Unexpected websocket handshake error: \(error)")
            return
        }
    }
}

@Test func websocketHeartbeatConfirmationCompletesAfterSuccessfulPong() async throws {
    try await PlexSessionEventsClient.confirmHeartbeat { completion in
        completion(nil)
    }
}

@Test func websocketHeartbeatConfirmationThrowsPingFailure() async throws {
    let error = URLError(.networkConnectionLost)

    do {
        try await PlexSessionEventsClient.confirmHeartbeat { completion in
            completion(error)
        }
        Issue.record("Expected heartbeat failure to surface")
    } catch let receivedError as URLError {
        #expect(receivedError.code == .networkConnectionLost)
    }
}

@Test func websocketHeartbeatConfirmationTimesOutWhenPongNeverReturns() async throws {
    do {
        try await PlexSessionEventsClient.confirmHeartbeat(
            sendPing: { _ in },
            timeout: .milliseconds(10)
        )
        Issue.record("Expected heartbeat timeout to surface")
    } catch let error as PlexSessionEventsError {
        guard case .heartbeatTimedOut = error else {
            Issue.record("Unexpected websocket heartbeat error: \(error)")
            return
        }
    }
}
