import CoreGraphics
import Observation
import SwiftUI

@MainActor
@Observable
final class PlexArtworkPresentationState {
    private let imageClient: PlexImageClient
    private let paletteExtractor: PlexArtworkPaletteExtractor
    private let primaryImageURL: URL?
    private let fallbackImageURL: URL?
    private let token: String
    private let wantsPalette: Bool

    private(set) var cgImage: CGImage?
    private(set) var palette: PlexArtworkPalette?
    var isLoading = false

    init(
        primaryImageURL: URL? = nil,
        fallbackImageURL: URL? = nil,
        token: String = "",
        wantsPalette: Bool = false,
        imageClient: PlexImageClient = PlexImageClient(),
        paletteExtractor: PlexArtworkPaletteExtractor = PlexArtworkPaletteExtractor()
    ) {
        self.primaryImageURL = primaryImageURL
        self.fallbackImageURL = fallbackImageURL
        self.token = token
        self.wantsPalette = wantsPalette
        self.imageClient = imageClient
        self.paletteExtractor = paletteExtractor

        hydrateFromCache()
    }

    var image: Image? {
        cgImage.map { Image(decorative: $0, scale: 1, orientation: .up) }
    }

    func load(
        primaryImageURL: URL?,
        fallbackImageURL: URL?,
        token: String,
        clientContext: PlexClientContext,
        wantsPalette: Bool
    ) async {
        let candidateURLs = [primaryImageURL, fallbackImageURL].compactMap { $0 }
        guard !candidateURLs.isEmpty else {
            cgImage = nil
            palette = nil
            isLoading = false
            return
        }

        if let cachedImage = imageClient.cachedCGImageResult(from: candidateURLs, token: token) {
            cgImage = cachedImage.image
            palette = wantsPalette ? resolvedPalette(for: cachedImage.image, sourceURL: cachedImage.sourceURL, token: token) : nil
            isLoading = false
            return
        }

        isLoading = true
        cgImage = nil
        palette = nil

        if Task.isCancelled {
            isLoading = false
            return
        }

        if let loadedImage = await imageClient.fetchCGImageResult(
            from: candidateURLs,
            token: token,
            clientContext: clientContext
        ) {
            cgImage = loadedImage.image
            palette = wantsPalette ? resolvedPalette(for: loadedImage.image, sourceURL: loadedImage.sourceURL, token: token) : nil
            isLoading = false
            return
        }

        isLoading = false
    }

    private func resolvedPalette(for image: CGImage, sourceURL: URL, token: String) -> PlexArtworkPalette? {
        if let cachedPalette = imageClient.cachedPalette(for: sourceURL, token: token) {
            return cachedPalette
        }

        guard let extractedPalette = paletteExtractor.extract(from: image) else {
            return nil
        }

        imageClient.cachePalette(extractedPalette, for: sourceURL, token: token)
        return extractedPalette
    }

    private func hydrateFromCache() {
        let candidateURLs = [primaryImageURL, fallbackImageURL].compactMap { $0 }
        guard !candidateURLs.isEmpty else {
            return
        }

        guard let cachedImage = imageClient.cachedCGImageResult(from: candidateURLs, token: token) else {
            return
        }

        cgImage = cachedImage.image
        palette = wantsPalette
            ? resolvedPalette(for: cachedImage.image, sourceURL: cachedImage.sourceURL, token: token)
            : nil
    }
}
