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
            "transcodeSession": {
              "key": "/transcode/sessions/abc"
            }
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
