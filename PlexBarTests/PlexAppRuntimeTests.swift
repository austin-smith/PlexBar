import PlexMockData
import Foundation
import Testing
@testable import PlexBar

@MainActor
@Test func defaultsToLiveRuntimeMode() {
    #expect(PlexAppRuntime.mode(arguments: ["PlexBar"]) == .live)
    #expect(PlexAppRuntime.makeImageSession(arguments: ["PlexBar"]) === URLSession.shared)
}

#if DEBUG
@MainActor
@Test func selectsMockRuntimeModeFromArgument() {
    #expect(PlexAppRuntime.mode(arguments: ["PlexBar", "--mock"]) == .mock)
}

@MainActor
@Test func mockAvatarsLoadAtRequestedSizesWithoutSeededCache() async throws {
    let session = PlexAppRuntime.makeImageSession(arguments: ["PlexBar", "--mock"])
    let payload = try PlexMockServerPayload.loadDefault()
    let server = PlexDebugMockServer.mockServer
    let serverURL = try #require(server.connections.first?.uri)
    let imageClient = PlexImageClient(
        session: session,
        cache: PlexImageMemoryCache(),
        requestCoordinator: PlexImageRequestCoordinator()
    )

    for user in payload.users {
        let request = try #require(PlexAvatarView.resolveRequest(
            thumb: user.avatar,
            serverURL: serverURL,
            serverToken: server.accessToken,
            userToken: PlexDebugMockServer.mockUserToken
        ))
        for maximumPixelSize in [60, 120] {
            #expect(imageClient.cachedCGImageResult(
                from: [request.url], token: request.token, maximumPixelSize: maximumPixelSize
            ) == nil)
            let result = try #require(await imageClient.fetchCGImageResult(
                from: [request.url],
                token: request.token,
                clientContext: PlexClientContext(clientIdentifier: "mock-avatar-tests"),
                maximumPixelSize: maximumPixelSize
            ))
            #expect(max(result.image.width, result.image.height) == maximumPixelSize)
        }
    }
}
#endif
