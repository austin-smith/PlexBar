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

@Test func appendsToReturnedEndpointPathWithoutDroppingItsQueryPairs() async throws {
    let serverURL = try #require(PlexURLBuilder.normalizeServerURL("https://plex.local:32400/base"))
    let endpointURL = PlexURLBuilder.endpointURL(
        serverURL: serverURL,
        path: "/provider/play-queue/?source=library&scope=audio",
        appendingPathComponent: "92"
    )

    #expect(endpointURL?.absoluteString == "https://plex.local:32400/base/provider/play-queue/92?source=library&scope=audio")
}

@Test func refusesToAppendToAnAbsoluteReturnedEndpoint() async throws {
    let serverURL = try #require(PlexURLBuilder.normalizeServerURL("https://plex.local:32400"))

    #expect(PlexURLBuilder.endpointURL(
        serverURL: serverURL,
        path: "https://other.example/play-queue",
        appendingPathComponent: "92"
    ) == nil)
}

@Test func refusesAnAbsoluteReturnedEndpointWithoutPathAppending() async throws {
    let serverURL = try #require(PlexURLBuilder.normalizeServerURL("https://plex.local:32400"))

    #expect(PlexURLBuilder.endpointURL(
        serverURL: serverURL,
        path: "https://other.example/provider/timeline?source=library"
    ) == nil)
}

@Test func appendsMultipleComponentsToReturnedEndpointWithoutDroppingItsQueryPairs() async throws {
    let serverURL = try #require(PlexURLBuilder.normalizeServerURL("https://plex.local:32400"))
    let endpointURL = PlexURLBuilder.endpointURL(
        serverURL: serverURL,
        path: "/provider/metadata/?source=library",
        appendingPathComponents: ["42", "refresh"]
    )

    #expect(endpointURL?.absoluteString == "https://plex.local:32400/provider/metadata/42/refresh?source=library")
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

@Test func buildsAspectPreservingPhotoURLWithoutUpscaling() async throws {
    let serverURL = try #require(PlexURLBuilder.normalizeServerURL("https://plex.local:32400"))
    let imageURL = PlexURLBuilder.transcodedPhotoURL(
        serverURL: serverURL,
        path: "/library/parts/700/1715112830/file.jpeg",
        width: 2_200,
        height: 1_466
    )

    #expect(imageURL?.absoluteString == "https://plex.local:32400/photo/:/transcode?url=/library/parts/700/1715112830/file.jpeg&width=2200&height=1466&minSize=0&upscale=0&rotate=1&quality=-1&format=jpeg")
    #expect(PlexURLBuilder.transcodedPhotoURL(
        serverURL: serverURL,
        path: "/library/parts/700/file.jpeg",
        width: 0,
        height: 1_000
    ) == nil)
}

@Test func buildsPlexAuthURLWithPinCode() async throws {
    let clientContext = PlexClientContext(clientIdentifier: "client-123")
    let authURL = try #require(clientContext.authURL(for: "pin-code"))
    let absoluteString = authURL.absoluteString

    #expect(absoluteString.contains(PlexRemoteService.authAppBaseURL.absoluteString + "/auth/#!?"))
    #expect(absoluteString.contains("clientID=client-123"))
    #expect(absoluteString.contains("code=pin-code"))
    #expect(absoluteString.contains("context%5Bdevice%5D%5BdeviceName%5D=Mac%20(PlexBar)"))
    #expect(!absoluteString.contains("forwardUrl="))
}
