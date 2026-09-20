import PlexClientKit
import Foundation

extension PlexAPIClient {
    func fetchDownloadArtwork(
        path: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> Data {
        guard let url = PlexURLBuilder.transcodedArtworkURL(
            serverURL: configuration.serverURL,
            path: path,
            width: 480,
            height: 720
        ) else {
            throw PlexAPIError.invalidServerURL
        }
        let request = PlexRequestBuilder(clientContext: configuration.clientContext).request(
            url: url,
            accept: "image/jpeg",
            token: configuration.token
        )
        return try await data(for: request)
    }
}
