import PlexClientKit
import CoreGraphics
import Observation
import SwiftUI

private struct SendableCGImageBox: @unchecked Sendable {
    let image: CGImage
}

@MainActor
@Observable
final class PlexArtworkPresentationState {
    private let imageClient: PlexImageClient
    private let extractPalette: @Sendable (CGImage) -> PlexArtworkPalette?
    private let primaryImageURL: URL?
    private let fallbackImageURL: URL?
    private let token: String
    private let wantsPalette: Bool
    private let maximumPixelSize: Int?
    private var loadGeneration = 0

    private(set) var cgImage: CGImage?
    private(set) var palette: PlexArtworkPalette?
    var isLoading = false

    init(
        primaryImageURL: URL? = nil,
        fallbackImageURL: URL? = nil,
        token: String = "",
        wantsPalette: Bool = false,
        maximumPixelSize: Int? = nil,
        imageClient: PlexImageClient = PlexImageClient(),
        extractPalette: @escaping @Sendable (CGImage) -> PlexArtworkPalette? = {
            PlexArtworkPaletteExtractor().extract(from: $0)
        }
    ) {
        self.primaryImageURL = primaryImageURL
        self.fallbackImageURL = fallbackImageURL
        self.token = token
        self.wantsPalette = wantsPalette
        self.maximumPixelSize = maximumPixelSize
        self.imageClient = imageClient
        self.extractPalette = extractPalette

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
        wantsPalette: Bool,
        maximumPixelSize: Int? = nil
    ) async {
        guard !Task.isCancelled else {
            return
        }

        loadGeneration &+= 1
        let generation = loadGeneration
        let candidateURLs = [primaryImageURL, fallbackImageURL].compactMap { $0 }
        guard !candidateURLs.isEmpty else {
            cgImage = nil
            palette = nil
            isLoading = false
            return
        }

        if let cachedImage = imageClient.cachedCGImageResult(
            from: candidateURLs,
            token: token,
            maximumPixelSize: maximumPixelSize
        ) {
            cgImage = cachedImage.image
            guard wantsPalette else {
                palette = nil
                isLoading = false
                return
            }

            if let cachedPalette = imageClient.cachedPalette(for: cachedImage.sourceURL, token: token) {
                palette = cachedPalette
                isLoading = false
                return
            }

            palette = nil
            isLoading = true
            let resolvedPalette = await resolvedPalette(
                for: cachedImage.image,
                sourceURL: cachedImage.sourceURL,
                token: token
            )
            guard isCurrentLoad(generation) else {
                return
            }
            palette = resolvedPalette
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
            clientContext: clientContext,
            maximumPixelSize: maximumPixelSize
        ) {
            guard isCurrentLoad(generation) else {
                return
            }
            cgImage = loadedImage.image
            guard wantsPalette else {
                isLoading = false
                return
            }

            let resolvedPalette = await resolvedPalette(
                for: loadedImage.image,
                sourceURL: loadedImage.sourceURL,
                token: token
            )
            guard isCurrentLoad(generation) else {
                return
            }
            palette = resolvedPalette
            isLoading = false
            return
        }

        if isCurrentLoad(generation) {
            isLoading = false
        }
    }

    private func resolvedPalette(for image: CGImage, sourceURL: URL, token: String) async -> PlexArtworkPalette? {
        if let cachedPalette = imageClient.cachedPalette(for: sourceURL, token: token) {
            return cachedPalette
        }

        let extractPalette = extractPalette
        let imageBox = SendableCGImageBox(image: image)
        guard let extractedPalette = await extractArtworkPalette(
            imageBox: imageBox,
            extractPalette: extractPalette
        ) else {
            return nil
        }

        imageClient.cachePalette(extractedPalette, for: sourceURL, token: token)
        return extractedPalette
    }

    private func isCurrentLoad(_ generation: Int) -> Bool {
        !Task.isCancelled && generation == loadGeneration
    }

    private func hydrateFromCache() {
        let candidateURLs = [primaryImageURL, fallbackImageURL].compactMap { $0 }
        guard !candidateURLs.isEmpty else {
            return
        }

        guard let cachedImage = imageClient.cachedCGImageResult(
            from: candidateURLs,
            token: token,
            maximumPixelSize: maximumPixelSize
        ) else {
            return
        }

        cgImage = cachedImage.image
        palette = wantsPalette
            ? imageClient.cachedPalette(for: cachedImage.sourceURL, token: token)
            : nil
    }
}

@concurrent
private func extractArtworkPalette(
    imageBox: SendableCGImageBox,
    extractPalette: @escaping @Sendable (CGImage) -> PlexArtworkPalette?
) async -> PlexArtworkPalette? {
    extractPalette(imageBox.image)
}
