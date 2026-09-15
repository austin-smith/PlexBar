import SwiftUI
import ImageIO

struct StudioImageView: View {
    let url: URL?
    var contentMode: ContentMode = .fit
    var revision = 0
    @State private var image: CGImage?

    var body: some View {
        Color.primary.opacity(0.035)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundStyle(.tertiary)
                }
            }
            .clipped()
        .task(id: "\(url?.path ?? ""):\(revision)") {
            image = nil
            guard let url else { return }
            let result = await Task.detached(priority: .userInitiated) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return Optional<CGImage>.none }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1200
                ] as CFDictionary)
            }.value
            guard !Task.isCancelled else { return }
            image = result
        }
    }
}
