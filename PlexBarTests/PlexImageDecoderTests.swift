@testable import PlexClientKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PlexBar

@Suite
struct PlexImageDecoderTests {
    @Test func decodesAndDownsamplesAwayFromTheCallingActor() async throws {
        let data = try pngData(width: 400, height: 200)

        let original = try #require(await PlexImageDecoder.decodeCGImage(from: data))
        #expect(original.image.width == 400)
        #expect(original.image.height == 200)

        let thumbnail = try #require(await PlexImageDecoder.decodeCGImage(
            from: data,
            maximumPixelSize: 100
        ))
        #expect(thumbnail.image.width == 100)
        #expect(thumbnail.image.height == 50)
    }

    @Test func rejectsMalformedImageData() async {
        let image = await PlexImageDecoder.decodeCGImage(from: Data("not an image".utf8))
        #expect(image == nil)
    }

    private func pngData(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
