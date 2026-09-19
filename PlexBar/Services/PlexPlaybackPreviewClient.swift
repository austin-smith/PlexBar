import Foundation

struct PlexPlaybackPreviewClient: Sendable {
    private let session: URLSession

    init(session: URLSession = PlexImageClient.defaultSession) {
        self.session = session
    }

    func image(
        for frame: PlexPlaybackPreviewFrame,
        source: PlexServerPlaybackPreviewSource
    ) async throws -> PlexCGImageBox {
        guard let url = PlexURLBuilder.endpointURL(serverURL: source.serverURL, path: frame.path) else {
            throw PlexAPIError.invalidServerURL
        }
        let request = PlexRequestBuilder(clientContext: source.clientContext).request(
            url: url, accept: "image/jpeg", token: source.token
        )
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else {
            throw PlexPlaybackPreviewError.invalidResponse
        }
        if response.statusCode == 404 { throw PlexPlaybackPreviewError.noIndex }
        guard response.statusCode == 200 else {
            throw PlexPlaybackPreviewError.httpStatus(response.statusCode)
        }
        guard response.mimeType == "image/jpeg",
              let image = await PlexImageDecoder.decodeCGImage(from: data, maximumPixelSize: 440) else {
            throw PlexPlaybackPreviewError.invalidImage
        }
        try Task.checkCancellation()
        return image
    }
}
