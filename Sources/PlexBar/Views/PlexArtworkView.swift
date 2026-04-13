import AppKit
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
    var showsPausedOverlay = false
    let imageClient: PlexImageClient

    @State private var image: Image?
    @State private var isLoading = false

    init(
        primaryImageURL: URL?,
        fallbackImageURL: URL?,
        token: String,
        clientContext: PlexClientContext,
        placeholderSymbol: String,
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat = 12,
        showsPausedOverlay: Bool = false,
        imageClient: PlexImageClient = PlexImageClient()
    ) {
        self.primaryImageURL = primaryImageURL
        self.fallbackImageURL = fallbackImageURL
        self.token = token
        self.clientContext = clientContext
        self.placeholderSymbol = placeholderSymbol
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.showsPausedOverlay = showsPausedOverlay
        self.imageClient = imageClient

        let cachedImage = imageClient.cachedImage(
            from: [primaryImageURL, fallbackImageURL].compactMap { $0 },
            token: token
        )
        _image = State(initialValue: cachedImage.map(Image.init(nsImage:)))
    }

    var body: some View {
        ZStack {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
                    .overlay {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
            }

            if showsPausedOverlay {
                pauseOverlay
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: requestKey) {
            await loadImage()
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

    @MainActor
    private func loadImage() async {
        let candidateURLs = [primaryImageURL, fallbackImageURL].compactMap { $0 }
        guard !candidateURLs.isEmpty else {
            image = nil
            isLoading = false
            return
        }

        if let cachedImage = imageClient.cachedImage(from: candidateURLs, token: token) {
            image = Image(nsImage: cachedImage)
            isLoading = false
            return
        }

        isLoading = true
        image = nil

        if Task.isCancelled {
            isLoading = false
            return
        }

        if let loadedImage = await imageClient.fetchImage(
            from: candidateURLs,
            token: token,
            clientContext: clientContext
        ) {
            image = Image(nsImage: loadedImage)
            isLoading = false
            return
        }

        isLoading = false
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

    private var pauseOverlay: some View {
        VStack {
            HStack {
                Spacer()

                Image(systemName: "pause.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.65), in: Circle())
            }

            Spacer()
        }
        .padding(8)
    }
}
