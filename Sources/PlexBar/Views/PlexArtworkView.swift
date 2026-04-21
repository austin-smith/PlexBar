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
    @State private var artwork: PlexArtworkPresentationState

    init(
        primaryImageURL: URL?,
        fallbackImageURL: URL?,
        token: String,
        clientContext: PlexClientContext,
        placeholderSymbol: String,
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat = 12
    ) {
        self.primaryImageURL = primaryImageURL
        self.fallbackImageURL = fallbackImageURL
        self.token = token
        self.clientContext = clientContext
        self.placeholderSymbol = placeholderSymbol
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        _artwork = State(initialValue: PlexArtworkPresentationState(
            primaryImageURL: primaryImageURL,
            fallbackImageURL: fallbackImageURL,
            token: token,
            wantsPalette: false
        ))
    }

    var body: some View {
        ZStack {
            if let image = artwork.image {
                image
                    .resizable()
                    .scaledToFill()
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
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: requestKey) {
            await artwork.load(
                primaryImageURL: primaryImageURL,
                fallbackImageURL: fallbackImageURL,
                token: token,
                clientContext: clientContext,
                wantsPalette: false
            )
        }
    }

    private var requestKey: String {
        [
            primaryImageURL?.absoluteString,
            fallbackImageURL?.absoluteString,
            clientContext.clientIdentifier,
            token,
        ]
        .compactMap { $0 }
        .joined(separator: "|")
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
