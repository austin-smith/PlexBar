import CoreGraphics
import Foundation
import Testing
@testable import PlexBar

@Test func artworkPaletteExtractorKeepsProminentPosterColors() async throws {
    let image = try #require(testImage(quadrants: [
        PlexPaletteColor(red: 0.92, green: 0.18, blue: 0.16),
        PlexPaletteColor(red: 0.18, green: 0.32, blue: 0.88),
        PlexPaletteColor(red: 0.95, green: 0.68, blue: 0.14),
        PlexPaletteColor(red: 0.12, green: 0.72, blue: 0.42),
    ]))

    let palette = try #require(PlexArtworkPaletteExtractor().extract(from: image))

    #expect(palette.colors.count == 4)
    #expect(palette.colors.contains { $0.red > 0.30 && $0.saturation > 0.45 })
    #expect(palette.colors.contains { $0.blue > 0.24 && $0.saturation > 0.45 })
}

@Test func artworkPaletteExtractorNormalizesColorsForReadableDarkMesh() async throws {
    let image = try #require(testImage(quadrants: [
        PlexPaletteColor(red: 0.98, green: 0.92, blue: 0.18),
        PlexPaletteColor(red: 0.88, green: 0.24, blue: 0.22),
        PlexPaletteColor(red: 0.24, green: 0.90, blue: 0.54),
        PlexPaletteColor(red: 0.25, green: 0.42, blue: 0.98),
    ]))

    let palette = try #require(PlexArtworkPaletteExtractor().extract(from: image))

    for color in palette.colors {
        #expect(color.brightness <= 0.42)
        #expect(color.brightness >= 0.18)
        #expect(color.saturation >= 0.24)
    }
}

@Test func artworkPaletteExtractorKeepsGrayscaleArtworkNeutral() async throws {
    let image = try #require(testImage(quadrants: [
        PlexPaletteColor(red: 0.80, green: 0.80, blue: 0.80),
        PlexPaletteColor(red: 0.60, green: 0.60, blue: 0.60),
        PlexPaletteColor(red: 0.35, green: 0.35, blue: 0.35),
        PlexPaletteColor(red: 0.22, green: 0.22, blue: 0.22),
    ]))

    let palette = try #require(PlexArtworkPaletteExtractor().extract(from: image))

    for color in palette.colors {
        #expect(abs(color.red - color.green) < 0.0001)
        #expect(abs(color.green - color.blue) < 0.0001)
    }
}

@Test func imageClientCachesPaletteByTokenizedURLKey() async throws {
    let client = PlexImageClient()
    let url = try #require(URL(string: "https://example.com/library/metadata/777/thumb"))
    let palette = PlexArtworkPalette(
        colors: [
            PlexPaletteColor(red: 0.2, green: 0.1, blue: 0.1),
            PlexPaletteColor(red: 0.1, green: 0.2, blue: 0.1),
            PlexPaletteColor(red: 0.1, green: 0.1, blue: 0.2),
            PlexPaletteColor(red: 0.2, green: 0.2, blue: 0.1),
        ]
    )

    client.cachePalette(palette, for: url, token: "token-777")

    #expect(client.cachedPalette(for: url, token: "token-777") == palette)
    #expect(client.cachedPalette(for: url, token: "different-token") == nil)
}

@Test func imageMemoryCacheStrictlyEvictsLeastRecentlyUsedImageByByteCost() async throws {
    let firstImage = try #require(testImage(
        width: 40,
        quadrants: repeatedColor(PlexPaletteColor(red: 0.72, green: 0.18, blue: 0.14))
    ))
    let secondImage = try #require(testImage(
        width: 40,
        quadrants: repeatedColor(PlexPaletteColor(red: 0.12, green: 0.32, blue: 0.82))
    ))
    let singleImageCost = firstImage.bytesPerRow * firstImage.height
    let cache = PlexImageMemoryCache(
        imageCountLimit: 4,
        imageCostLimit: singleImageCost,
        paletteCountLimit: 4
    )

    cache.insert(firstImage, for: "first")
    cache.insert(secondImage, for: "second")

    #expect(cache.cgImage(for: "first") == nil)
    #expect(cache.cgImage(for: "second") != nil)
}

@Test func imageMemoryCacheStrictlyBoundsPaletteCount() async throws {
    let cache = PlexImageMemoryCache(
        imageCountLimit: 1,
        imageCostLimit: 1,
        paletteCountLimit: 1
    )
    let first = PlexArtworkPalette(colors: repeatedColor(
        PlexPaletteColor(red: 0.18, green: 0.28, blue: 0.38)
    ))
    let second = PlexArtworkPalette(colors: repeatedColor(
        PlexPaletteColor(red: 0.48, green: 0.38, blue: 0.28)
    ))

    cache.insert(first, for: "first")
    cache.insert(second, for: "second")

    #expect(cache.palette(for: "first") == nil)
    #expect(cache.palette(for: "second") == second)
}

@Test func imageMemoryCacheRefreshesLeastRecentlyUsedOrderOnRead() async throws {
    let firstImage = try #require(testImage(
        width: 20,
        quadrants: repeatedColor(PlexPaletteColor(red: 0.72, green: 0.18, blue: 0.14))
    ))
    let secondImage = try #require(testImage(
        width: 20,
        quadrants: repeatedColor(PlexPaletteColor(red: 0.12, green: 0.32, blue: 0.82))
    ))
    let thirdImage = try #require(testImage(
        width: 20,
        quadrants: repeatedColor(PlexPaletteColor(red: 0.18, green: 0.72, blue: 0.32))
    ))
    let totalCost = (firstImage.bytesPerRow * firstImage.height) * 3
    let cache = PlexImageMemoryCache(
        imageCountLimit: 2,
        imageCostLimit: totalCost,
        paletteCountLimit: 1
    )

    cache.insert(firstImage, for: "first")
    cache.insert(secondImage, for: "second")
    #expect(cache.cgImage(for: "first") != nil)
    cache.insert(thirdImage, for: "third")

    #expect(cache.cgImage(for: "first") != nil)
    #expect(cache.cgImage(for: "second") == nil)
    #expect(cache.cgImage(for: "third") != nil)
}

@MainActor
@Test func artworkPresentationStateHydratesCachedArtworkSynchronously() async throws {
    let client = PlexImageClient()
    let url = try #require(URL(string: "https://example.com/library/metadata/888/thumb"))
    let image = try #require(testImage(quadrants: [
        PlexPaletteColor(red: 0.78, green: 0.16, blue: 0.14),
        PlexPaletteColor(red: 0.18, green: 0.28, blue: 0.82),
        PlexPaletteColor(red: 0.86, green: 0.68, blue: 0.18),
        PlexPaletteColor(red: 0.14, green: 0.64, blue: 0.40),
    ]))

    let palette = try #require(PlexArtworkPaletteExtractor().extract(from: image))
    client.cachePalette(palette, for: url, token: "token-888")
    let cache = PlexImageMemoryCache.shared
    cache.insert(image, for: "\(url.absoluteString)|token-888")

    let state = PlexArtworkPresentationState(
        primaryImageURL: url,
        token: "token-888",
        wantsPalette: true,
        imageClient: client
    )

    #expect(state.cgImage != nil)
    #expect(state.palette == palette)
    #expect(state.isLoading == false)
}

@MainActor
@Test func artworkPresentationStateDoesNotPublishSupersededPalette() async throws {
    let client = PlexImageClient()
    let firstURL = try #require(URL(string: "https://example.com/library/metadata/991/thumb"))
    let secondURL = try #require(URL(string: "https://example.com/library/metadata/992/thumb"))
    let firstImage = try #require(testImage(
        width: 40,
        quadrants: repeatedColor(PlexPaletteColor(red: 0.86, green: 0.16, blue: 0.12))
    ))
    let secondImage = try #require(testImage(
        width: 44,
        quadrants: repeatedColor(PlexPaletteColor(red: 0.12, green: 0.24, blue: 0.88))
    ))
    let firstPalette = try #require(PlexArtworkPaletteExtractor().extract(from: firstImage))
    let secondPalette = try #require(PlexArtworkPaletteExtractor().extract(from: secondImage))
    let cache = PlexImageMemoryCache.shared
    cache.insert(firstImage, for: firstURL.absoluteString)
    cache.insert(secondImage, for: secondURL.absoluteString)

    let gate = PaletteExtractionGate(
        delayedImageWidth: firstImage.width,
        delayedPalette: firstPalette,
        immediatePalette: secondPalette
    )
    let state = PlexArtworkPresentationState(
        imageClient: client,
        extractPalette: gate.extract
    )
    let context = PlexClientContext(clientIdentifier: "palette-supersession-test")

    let firstLoad = Task {
        await state.load(
            primaryImageURL: firstURL,
            fallbackImageURL: nil,
            token: "",
            clientContext: context,
            wantsPalette: true
        )
    }
    await Task.detached {
        gate.waitUntilDelayedExtractionStarts()
    }.value

    await state.load(
        primaryImageURL: secondURL,
        fallbackImageURL: nil,
        token: "",
        clientContext: context,
        wantsPalette: true
    )
    #expect(state.palette == secondPalette)

    gate.finishDelayedExtraction()
    await firstLoad.value

    #expect(state.palette == secondPalette)
    #expect(state.cgImage?.width == secondImage.width)
    #expect(state.isLoading == false)
}

private final class PaletteExtractionGate: @unchecked Sendable {
    private let delayedImageWidth: Int
    private let delayedPalette: PlexArtworkPalette
    private let immediatePalette: PlexArtworkPalette
    private let delayedExtractionStarted = DispatchSemaphore(value: 0)
    private let allowDelayedExtractionToFinish = DispatchSemaphore(value: 0)

    init(
        delayedImageWidth: Int,
        delayedPalette: PlexArtworkPalette,
        immediatePalette: PlexArtworkPalette
    ) {
        self.delayedImageWidth = delayedImageWidth
        self.delayedPalette = delayedPalette
        self.immediatePalette = immediatePalette
    }

    func extract(from image: CGImage) -> PlexArtworkPalette? {
        guard image.width == delayedImageWidth else {
            return immediatePalette
        }

        delayedExtractionStarted.signal()
        allowDelayedExtractionToFinish.wait()
        return delayedPalette
    }

    func waitUntilDelayedExtractionStarts() {
        delayedExtractionStarted.wait()
    }

    func finishDelayedExtraction() {
        allowDelayedExtractionToFinish.signal()
    }
}

private func repeatedColor(_ color: PlexPaletteColor) -> [PlexPaletteColor] {
    Array(repeating: color, count: 4)
}

private func testImage(width: Int = 40, quadrants: [PlexPaletteColor]) -> CGImage? {
    guard quadrants.count == 4 else {
        return nil
    }

    let height = width
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    let bitsPerComponent = 8
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    var buffer = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

    guard let context = CGContext(
        data: &buffer,
        width: width,
        height: height,
        bitsPerComponent: bitsPerComponent,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }

    let halfWidth = CGFloat(width) / 2
    let rects = [
        CGRect(x: 0, y: halfWidth, width: halfWidth, height: halfWidth),
        CGRect(x: halfWidth, y: halfWidth, width: halfWidth, height: halfWidth),
        CGRect(x: 0, y: 0, width: halfWidth, height: halfWidth),
        CGRect(x: halfWidth, y: 0, width: halfWidth, height: halfWidth),
    ]

    for (color, rect) in zip(quadrants, rects) {
        context.setFillColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
        context.fill(rect)
    }

    return context.makeImage()
}
