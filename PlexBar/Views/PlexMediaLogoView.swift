import SwiftUI

struct PlexMediaLogoView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let imageURL: URL?
    let fallbackTitle: String
    let accessibilityLabel: String
    let token: String
    let clientContext: PlexClientContext
    let maximumWidth: CGFloat
    let maximumHeight: CGFloat
    @State private var artwork: PlexArtworkPresentationState

    init(
        imageURL: URL?,
        fallbackTitle: String,
        accessibilityLabel: String? = nil,
        token: String,
        clientContext: PlexClientContext,
        maximumWidth: CGFloat = 320,
        maximumHeight: CGFloat = 112
    ) {
        self.imageURL = imageURL
        self.fallbackTitle = fallbackTitle
        self.accessibilityLabel = accessibilityLabel ?? fallbackTitle
        self.token = token
        self.clientContext = clientContext
        self.maximumWidth = maximumWidth
        self.maximumHeight = maximumHeight
        _artwork = State(initialValue: PlexArtworkPresentationState(
            primaryImageURL: imageURL,
            token: token,
            wantsPalette: false,
            maximumPixelSize: 1_000
        ))
    }

    var body: some View {
        Group {
            if let cgImage = artwork.cgImage {
                let fittedSize = fittedLogoSize(for: cgImage)
                Image(decorative: cgImage, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: fittedSize.width,
                        height: fittedSize.height,
                        alignment: .leading
                    )
                    .transition(.opacity)
            } else {
                Text(fallbackTitle)
                    .font(.system(size: 42, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .frame(
                        width: maximumWidth,
                        alignment: .bottomLeading
                    )
                    .frame(maxHeight: maximumHeight, alignment: .bottomLeading)
                    .transition(.opacity)
            }
        }
        .animation(
            PlexMotion.contentReplacementAnimation(reduceMotion: accessibilityReduceMotion),
            value: artwork.cgImage != nil
        )
        .frame(maxWidth: maximumWidth, alignment: .bottomLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .task(id: requestKey) {
            await artwork.load(
                primaryImageURL: imageURL,
                fallbackImageURL: nil,
                token: token,
                clientContext: clientContext,
                wantsPalette: false,
                maximumPixelSize: 1_000
            )
        }
    }

    private var requestKey: String {
        [imageURL?.absoluteString, token, clientContext.clientIdentifier]
            .compactMap { $0 }
            .joined(separator: "|")
    }

    private func fittedLogoSize(for image: CGImage) -> CGSize {
        guard image.width > 0, image.height > 0 else {
            return CGSize(width: maximumWidth, height: maximumHeight)
        }

        let aspectRatio = CGFloat(image.width) / CGFloat(image.height)
        let width = min(maximumWidth, maximumHeight * aspectRatio)
        return CGSize(width: width, height: width / aspectRatio)
    }
}
