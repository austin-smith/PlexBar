import SwiftUI

struct PlexPhotoDetailStage: View {
    let presentation: PlexPhotoPresentation
    let title: String
    let serverURL: URL?
    let token: String
    let clientContext: PlexClientContext
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geometry in
            let displaySize = presentation.fittedSize(in: geometry.size)
            let requestSize = presentation.requestPixelSize(
                for: displaySize,
                displayScale: displayScale
            )

            PlexArtworkView(
                primaryImageURL: photoURL(
                    width: Int(requestSize.width),
                    height: Int(requestSize.height)
                ),
                fallbackImageURL: fallbackURL,
                token: token,
                clientContext: clientContext,
                placeholderSymbol: "photo",
                width: displaySize.width,
                height: displaySize.height,
                cornerRadius: 12,
                contentMode: .fit
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: 1_100)
        .frame(height: 620)
        .padding(12)
        .background(.black.opacity(0.22), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    private var fallbackURL: URL? {
        guard let serverURL else {
            return nil
        }
        return PlexURLBuilder.mediaURL(
            serverURL: serverURL,
            path: presentation.fallbackArtworkPath
        )
    }

    private func photoURL(width: Int, height: Int) -> URL? {
        guard let serverURL else {
            return nil
        }
        return PlexURLBuilder.transcodedPhotoURL(
            serverURL: serverURL,
            path: presentation.sourcePath,
            width: width,
            height: height
        )
    }
}
