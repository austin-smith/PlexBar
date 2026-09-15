import PlexModels
import Foundation
import Testing
@testable import PlexBar

struct PlexSessionPlaybackDetailsTests {
    @Test func directPlayUsesSelectedTracksAndSessionBandwidth() throws {
        let details = try details(#"""
        {"title":"Example","Player":{},"Session":{"bandwidth":13900},"Media":[{"Part":[{
          "decision":"directplay","Stream":[
            {"streamType":1,"displayTitle":"1080p (H.264)"},
            {"streamType":2,"selected":false,"displayTitle":"French (AAC)"},
            {"streamType":2,"selected":true,"displayTitle":"English (AC3 5.1)"},
            {"streamType":3,"selected":false,"codec":"srt"}
          ]
        }]}]}
        """#)
        #expect(details.method == "Direct Play")
        #expect(details.bandwidth != nil)
        #expect(details.rows.map(\.source) == ["1080p (H.264)", "English (AC3 5.1)", "None"])
        #expect(details.rows[1].output == nil)
        #expect(!details.usesHardware)
    }

    @Test(arguments: [
        (#""transcodeHwRequested":true"#, false),
        (#""transcodeHwEncoding":"""#, false),
        (#""transcodeHwEncoding":"none""#, false),
        (#""transcodeHwEncoding":"videotoolbox""#, true),
        (#""transcodeHwDecoding":"nvdec""#, true)
    ])
    func hardwareRequiresAnActiveEngine(fields: String, expected: Bool) throws {
        let details = try details("""
        {"title":"Example","Player":{},"live":true,"TranscodeSession":{
          "videoDecision":"transcode","videoCodec":"h264","sourceVideoCodec":"hevc",\(fields)
        }}
        """)
        #expect(details.usesHardware == expected)
        #expect(details.rows[0].output == (expected ? "H.264 · HW" : "H.264"))
    }

    @Test func subtitleConversionDoesNotMarkCopiedVideoAsHardwareTranscoding() throws {
        let details = try details(#"""
        {"title":"Example","Player":{},"Media":[{"Part":[{"decision":"transcode","Stream":[
          {"streamType":1,"decision":"copy","codec":"h264"},
          {"streamType":3,"selected":true,"decision":"transcode","codec":"ass","language":"English"}
        ]}]}],"TranscodeSession":{"videoDecision":"copy","transcodeHwEncoding":"videotoolbox"}}
        """#)
        #expect(details.method == "Direct Stream")
        #expect(!details.usesHardware)
        #expect(details.rows.last?.source == "English")
        #expect(details.rows.last?.output == "ASS")
    }

    @Test func missingBandwidthAndAmbiguousAudioAreNotInvented() throws {
        let details = try details(#"""
        {"title":"Example","Player":{},"Session":{"bandwidth":-1},"Media":[{"Part":[{
          "decision":"directplay","Stream":[
            {"streamType":2,"codec":"aac"},{"streamType":2,"codec":"ac3"}
          ]
        }]}]}
        """#)
        #expect(details.bandwidth == nil)
        #expect(details.rows.first?.source == "Unavailable")
    }

    @Test func mockHTTPPreservesTechnicalFields() async throws {
        let client = PlexAPIClient(session: PlexDebugMockServer.makeSession())
        let sessions = try await client.fetchSessions(using: PlexConnectionConfiguration(
            serverURL: PlexDebugMockServer.mockResolvedConnection.url,
            token: "plexbar-debug-mock-server-token",
            clientContext: PlexClientContext(clientIdentifier: "details-tests")
        ))
        let transcoding = try #require(sessions.first { $0.deliveryMethod == .transcoding })
        let details = PlexSessionPlaybackDetails(session: transcoding)
        #expect(details.usesHardware)
        #expect(details.rows[0].source == "1080p (HEVC Main 10)")
        #expect(details.rows[0].output == "H.264 · 8 Mbps · HW")
        #expect(details.rows[2].source == "English (SRT)")
    }

    @Test func omittedDirectPlayDecisionMatchesTheSummary() throws {
        let details = try details(#"""
        {"title":"Example","Player":{},"Media":[{"Part":[{
          "Stream":[{"streamType":1,"codec":"h264"}]
        }]}]}
        """#)
        #expect(details.method == "Direct Play")
        #expect(details.rows[0].output == nil)
    }

    @Test func absentTechnicalDataRemainsUnavailable() throws {
        let details = try details(#"{"title":"Example","Player":{}}"#)
        #expect(details.rows.map(\.source) == ["Unavailable", "Unavailable"])
        #expect(details.rows.allSatisfy { $0.output == nil })
    }

    @Test func outputTrackBitratesAreDistinctFromSessionBandwidth() throws {
        // Shape of the live Plex response: displayTitle describes the source,
        // while codec and bitrate describe the selected output track.
        let details = try details(#"""
        {"title":"Example","Player":{},"Session":{"bandwidth":21300},"Media":[{"Part":[{
          "decision":"transcode","Stream":[
            {"streamType":1,"decision":"transcode","codec":"h264","bitrate":20000,"displayTitle":"1080p (HEVC Main 10)"},
            {"streamType":2,"selected":true,"decision":"transcode","codec":"aac","bitrate":"256","displayTitle":"English (EAC3 5.1)"},
            {"streamType":3,"selected":true,"decision":"burn","codec":"ass","displayTitle":"English Forced (ASS)"}
          ]
        }]}]}
        """#)
        #expect(details.rows[0].source == "1080p (HEVC Main 10)")
        #expect(details.rows[0].output == "H.264 · 20 Mbps")
        #expect(details.rows[1].source == "English (EAC3 5.1)")
        #expect(details.rows[1].output == "AAC · 256 Kbps")
        #expect(details.rows[2].source == "English Forced (ASS)")
        #expect(details.rows[2].output == "Burn In")
    }

    @Test(arguments: ["null", "0", "-1"])
    func unavailableTrackBitrateDoesNotUseSessionBandwidth(bitrate: String) throws {
        let details = try details("""
        {"title":"Example","Player":{},"Session":{"bandwidth":21300},"Media":[{"Part":[{
          "decision":"transcode","Stream":[
            {"streamType":2,"selected":true,"decision":"transcode","codec":"aac","bitrate":\(bitrate)}
          ]
        }]}]}
        """)
        #expect(details.rows[0].source == "Unavailable")
        #expect(details.rows[0].output == "AAC")
    }

    @Test func copiedTracksAndUnchangedSubtitlesHaveDistinctPresentation() throws {
        let details = try details(#"""
        {"title":"Example","Player":{},"Media":[{"Part":[{"decision":"transcode","Stream":[
          {"streamType":1,"decision":"copy","codec":"h264","bitrate":3775},
          {"streamType":3,"selected":true,"decision":"copy","codec":"srt","displayTitle":"English (SRT)"}
        ]}]}]}
        """#)
        #expect(details.rows[0].output == "Direct Stream · 3.8 Mbps")
        #expect(details.rows[1].output == nil)
    }

    @Test func trackBitrateFormattingRespectsLocale() {
        #expect(PlexSessionPlaybackDetails.trackBitrateText(kbps: 3775, locale: Locale(identifier: "de_DE")) == "3,8 Mbps")
        #expect(PlexSessionPlaybackDetails.trackBitrateText(kbps: 256, locale: Locale(identifier: "en_US")) == "256 Kbps")
    }

    private func details(_ json: String) throws -> PlexSessionPlaybackDetails {
        PlexSessionPlaybackDetails(session: try JSONDecoder().decode(PlexSession.self, from: Data(json.utf8)))
    }
}
