import SwiftUI

struct PlexArtworkView: View {
    let primaryImageURL: URL?
    let fallbackImageURL: URL?
    let token: String
    let clientContext: PlexClientContext
    let placeholderSymbol: String
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = 12
    var contentMode: ContentMode = .fill
    @State private var artwork: PlexArtworkPresentationState

    init(
        primaryImageURL: URL?,
        fallbackImageURL: URL?,
        token: String,
        clientContext: PlexClientContext,
        placeholderSymbol: String,
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat = 12,
        contentMode: ContentMode = .fill
    ) {
        self.primaryImageURL = primaryImageURL
        self.fallbackImageURL = fallbackImageURL
        self.token = token
        self.clientContext = clientContext
        self.placeholderSymbol = placeholderSymbol
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.contentMode = contentMode
        let maximumPixelSize = Int(ceil(max(width, height) * 2))
        _artwork = State(initialValue: PlexArtworkPresentationState(
            primaryImageURL: primaryImageURL,
            fallbackImageURL: fallbackImageURL,
            token: token,
            wantsPalette: false,
            maximumPixelSize: maximumPixelSize
        ))
    }

    var body: some View {
        ZStack {
            if let image = artwork.image {
                artworkContent(image)
            } else {
                placeholder
                    .overlay {
                        if artwork.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
            }
        }
        .frame(width: width, height: height)
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: requestKey) {
            await artwork.load(
                primaryImageURL: primaryImageURL,
                fallbackImageURL: fallbackImageURL,
                token: token,
                clientContext: clientContext,
                wantsPalette: false,
                maximumPixelSize: maximumPixelSize
            )
        }
    }

    @ViewBuilder
    private func artworkContent(_ image: Image) -> some View {
        switch contentMode {
        case .fit:
            image
                .resizable()
                .scaledToFit()
        case .fill:
            image
                .resizable()
                .scaledToFill()
        }
    }

    private var requestKey: String {
        [
            primaryImageURL?.absoluteString,
            fallbackImageURL?.absoluteString,
            clientContext.clientIdentifier,
            token,
            String(maximumPixelSize),
        ]
        .compactMap { $0 }
        .joined(separator: "|")
    }

    private var maximumPixelSize: Int {
        Int(ceil(max(width, height) * 2))
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.08),
                    Color.white.opacity(0.03),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: placeholderSymbol)
                .font(.system(size: min(width, height) * 0.28, weight: .light))
                .foregroundStyle(.tertiary)
        }
    }
}
