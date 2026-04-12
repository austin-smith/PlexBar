import Foundation
import Testing
@testable import PlexBar

@Test func normalizesServerURLAndDropsTrailingSlash() async throws {
    let url = PlexURLBuilder.normalizeServerURL("192.168.1.25:32400/")

    #expect(url?.absoluteString == "http://192.168.1.25:32400")
}

@Test func buildsArtworkURLWithoutEmbeddingToken() async throws {
    let serverURL = try #require(PlexURLBuilder.normalizeServerURL("http://plex.local:32400"))
    let imageURL = PlexURLBuilder.mediaURL(
        serverURL: serverURL,
        path: "/library/metadata/146/thumb/1715112830"
    )

    #expect(imageURL?.absoluteString == "http://plex.local:32400/library/metadata/146/thumb/1715112830")
}

@Test func buildsTranscodedArtworkURL() async throws {
    let serverURL = try #require(PlexURLBuilder.normalizeServerURL("https://plex.local:32400"))
    let imageURL = PlexURLBuilder.transcodedArtworkURL(
        serverURL: serverURL,
        path: "/library/metadata/146/thumb/1715112830",
        width: 176,
        height: 264
    )

    #expect(imageURL?.absoluteString == "https://plex.local:32400/photo/:/transcode?url=/library/metadata/146/thumb/1715112830&width=176&height=264&minSize=1&upscale=1&format=jpeg")
}

@Test func buildsPlexAuthURLWithPinCode() async throws {
    let clientContext = PlexClientContext(clientIdentifier: "client-123")
    let authURL = try #require(clientContext.authURL(for: "pin-code"))
    let absoluteString = authURL.absoluteString

    #expect(absoluteString.contains("https://app.plex.tv/auth/#!?"))
    #expect(absoluteString.contains("clientID=client-123"))
    #expect(absoluteString.contains("code=pin-code"))
    #expect(absoluteString.contains("context%5Bdevice%5D%5BdeviceName%5D=Mac%20(PlexBar)"))
    #expect(!absoluteString.contains("forwardUrl="))
}
