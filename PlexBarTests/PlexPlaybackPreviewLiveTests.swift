import Foundation
import Testing
@testable import PlexBar

/// Explicitly opt in and supply PLEXBAR_LIVE_PREVIEW_SERVER_URL/TOKEN: these
/// tests read the specified server, but never
/// change metadata, generate indexes, start transcodes, or report playback.
struct PlexPlaybackPreviewLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PLEXBAR_LIVE_PREVIEW_TESTS"] == "1"))
    func retrievesRealPreviewImagesForSelectedMediaVersions() async throws {
        let environment = ProcessInfo.processInfo.environment
        let ratingKeys = try #require(environment["PLEXBAR_LIVE_PREVIEW_ITEMS"])
            .split(separator: ",").map(String.init)
        try #require(!ratingKeys.isEmpty)
        let serverURL = try #require(environment["PLEXBAR_LIVE_PREVIEW_SERVER_URL"].flatMap(URL.init(string:)))
        let token = try #require(environment["PLEXBAR_LIVE_PREVIEW_TOKEN"])
        let context = PlexClientContext(clientIdentifier: "plexbar-preview-api-validation")
        let configuration = PlexConnectionConfiguration(serverURL: serverURL, token: token, clientContext: context)
        let client = PlexPlaybackPreviewClient()

        for ratingKey in ratingKeys {
            let item = try await PlexAPIClient().fetchMediaMetadata(ratingKey: ratingKey, using: configuration)
            for media in item.media {
                for part in media.parts {
                    try #require(part.indexes == "sd")
                    let source = PlexServerPlaybackPreviewSource(
                        serverURL: serverURL, token: token, clientContext: context,
                        sessionIdentifier: "live-api-test", parts: [part]
                    )
                    let duration = Double(try #require(part.duration)) / 1_000
                    for time in [0, 30, duration / 2, duration] {
                        let image = try await client.image(for: source.frame(at: time), source: source)
                        #expect(image.image.width > 0 && image.image.height > 0)
                        #expect(image.image.width <= 440 && image.image.height <= 440)
                    }
                }
            }
        }

        let missingPart = try #require(environment["PLEXBAR_LIVE_PREVIEW_MISSING_PART"].flatMap(Int.init))
        let source = PlexServerPlaybackPreviewSource(
            serverURL: serverURL, token: token, clientContext: context,
            sessionIdentifier: "live-api-test", parts: []
        )
        await #expect(throws: PlexPlaybackPreviewError.noIndex) {
            try await client.image(
                for: PlexPlaybackPreviewFrame(partID: missingPart, partKey: nil, offsetMilliseconds: 30_000), source: source
            )
        }
    }
}
