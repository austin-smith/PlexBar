import PlexClientKit

extension PlexNowPlayingArtworkLoader {
    convenience init(imageClient: PlexImageClient = PlexImageClient()) {
        self.init { request in
            await imageClient.fetchCGImageResult(
                from: request.candidateURLs,
                token: request.token,
                clientContext: request.clientContext,
                maximumPixelSize: PlexNowPlayingArtworkRequest.maximumPixelSize
            ).map { PlexCGImageBox($0.image) }
        }
    }

}
