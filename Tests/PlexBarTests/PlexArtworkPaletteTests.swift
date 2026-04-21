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

private func testImage(quadrants: [PlexPaletteColor]) -> CGImage? {
    guard quadrants.count == 4 else {
        return nil
    }

    let width = 40
    let height = 40
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

    let rects = [
        CGRect(x: 0, y: 20, width: 20, height: 20),
        CGRect(x: 20, y: 20, width: 20, height: 20),
        CGRect(x: 0, y: 0, width: 20, height: 20),
        CGRect(x: 20, y: 0, width: 20, height: 20),
    ]

    for (color, rect) in zip(quadrants, rects) {
        context.setFillColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
        context.fill(rect)
    }

    return context.makeImage()
}
