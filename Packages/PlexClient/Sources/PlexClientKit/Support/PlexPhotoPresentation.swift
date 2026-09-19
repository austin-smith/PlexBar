import PlexModels
import CoreGraphics
import Foundation

public struct PlexPhotoPresentation: Equatable, Sendable {
    public let sourcePath: String?
    public let fallbackArtworkPath: String?
    public let pixelWidth: Int?
    public let pixelHeight: Int?

    public init?(item: PlexMediaItem) {
        guard item.type?.lowercased() == "photo" else {
            return nil
        }

        let media = item.media.first(where: {
            $0.selected == true && Self.sourcePart(in: $0) != nil
        })
            ?? item.media.first(where: { Self.sourcePart(in: $0) != nil })
            ?? item.media.first(where: { $0.selected == true })
            ?? item.media.first
        let part = media?.parts.first(where: {
            $0.selected == true && $0.key?.nilIfBlank != nil
        }) ?? media?.parts.first(where: { $0.key?.nilIfBlank != nil })
        let artworkPath = item.thumb?.nilIfBlank ?? item.composite?.nilIfBlank
        let sourcePath = part?.key?.nilIfBlank ?? artworkPath

        self.sourcePath = sourcePath
        fallbackArtworkPath = sourcePath != artworkPath ? artworkPath : nil
        pixelWidth = media?.width.flatMap { $0 > 0 ? $0 : nil }
        pixelHeight = media?.height.flatMap { $0 > 0 ? $0 : nil }
    }

    public var dimensionsText: String? {
        guard let pixelWidth, let pixelHeight else {
            return nil
        }
        return "\(pixelWidth.formatted()) × \(pixelHeight.formatted())"
    }

    public func fittedSize(in availableSize: CGSize) -> CGSize {
        let availableWidth = max(availableSize.width, 0)
        let availableHeight = max(availableSize.height, 0)
        guard availableWidth > 0, availableHeight > 0,
              let pixelWidth, let pixelHeight else {
            return CGSize(width: availableWidth, height: availableHeight)
        }

        let scale = min(
            availableWidth / CGFloat(pixelWidth),
            availableHeight / CGFloat(pixelHeight)
        )
        return CGSize(
            width: CGFloat(pixelWidth) * scale,
            height: CGFloat(pixelHeight) * scale
        )
    }

    public func requestPixelSize(for displaySize: CGSize, displayScale: CGFloat) -> CGSize {
        let scale = displayScale.isFinite ? max(displayScale, 1) : 1
        return CGSize(
            width: max(ceil(displaySize.width * scale), 1),
            height: max(ceil(displaySize.height * scale), 1)
        )
    }

    private static func sourcePart(in media: PlexMediaVersion) -> PlexMediaPart? {
        media.parts.first(where: { $0.key?.nilIfBlank != nil })
    }
}
