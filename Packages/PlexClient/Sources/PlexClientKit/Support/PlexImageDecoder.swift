import CoreGraphics
import Foundation
import ImageIO

public enum PlexImageDecoder {
    @concurrent
    public static func decodeCGImage(
        from data: Data,
        maximumPixelSize: Int? = nil
    ) async -> PlexCGImageBox? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        if let maximumPixelSize, maximumPixelSize > 0 {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
                .map(PlexCGImageBox.init)
        }

        return CGImageSourceCreateImageAtIndex(source, 0, nil)
            .map(PlexCGImageBox.init)
    }
}

public final class PlexCGImageBox: @unchecked Sendable {
    public let image: CGImage

    public init(_ image: CGImage) {
        self.image = image
    }
}
