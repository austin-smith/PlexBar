import AppKit
import SwiftUI

struct StreamCardView: View {
    let session: PlexSession
    let settingsStore: PlexSettingsStore

    private var clientContext: PlexClientContext {
        PlexClientContext(clientIdentifier: settingsStore.clientIdentifier)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PosterThumbnailView(
                primaryImageURL: posterURL,
                fallbackImageURL: transcodedPosterURL,
                token: settingsStore.trimmedServerToken,
                clientContext: clientContext,
                isPaused: session.isPaused,
                placeholderSymbol: session.contentKind.contentMetaSymbolName
            )

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.headline)
                        .font(.headline)
                        .lineLimit(2)

                    if session.contentKind == .tv || session.contentKind == .liveTV,
                       let metaLine = session.contentMetaLine,
                       let subtitle = session.contentSubtitle {
                        HStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: session.contentKind.contentMetaSymbolName)
                                    .foregroundStyle(.tertiary)
                                Text(metaLine)
                                    .foregroundStyle(.secondary)
                            }
                            Text(subtitle)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .font(.footnote)
                    } else if let subtitle = session.contentSubtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if session.contentKind != .tv,
                       session.contentKind != .liveTV,
                       let metaLine = session.contentMetaLine {
                        HStack(spacing: 6) {
                            Image(systemName: session.contentKind.contentMetaSymbolName)
                                .foregroundStyle(.tertiary)
                            Text(metaLine)
                                .foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                        .lineLimit(1)
                    }
                }

                Spacer(minLength: 14)

                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .overlay(.white.opacity(0.08))
                        .padding(.bottom, 2)

                    Text(session.playbackLine)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let progress = session.progress {
                        ProgressView(value: progress)
                            .tint(.orange)
                    }

                    UserIdentityRow(
                        userName: session.userDisplayName,
                        playerName: session.playerDisplayName,
                        thumb: session.user?.thumb,
                        serverURL: settingsStore.normalizedServerURL,
                        serverToken: settingsStore.trimmedServerToken,
                        userToken: settingsStore.trimmedUserToken,
                        clientContext: clientContext
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var posterURL: URL? {
        guard let serverURL = settingsStore.normalizedServerURL else {
            return nil
        }

        return PlexURLBuilder.mediaURL(
            serverURL: serverURL,
            path: session.posterPath
        )
    }

    private var transcodedPosterURL: URL? {
        guard let serverURL = settingsStore.normalizedServerURL else {
            return nil
        }

        return PlexURLBuilder.transcodedArtworkURL(
            serverURL: serverURL,
            path: session.posterPath,
            width: 176,
            height: 264
        )
    }

}

private struct PosterThumbnailView: View {
    let primaryImageURL: URL?
    let fallbackImageURL: URL?
    let token: String
    let clientContext: PlexClientContext
    let isPaused: Bool
    let placeholderSymbol: String
    let imageClient: PlexImageClient

    @State private var image: Image?
    @State private var isLoading = false

    init(
        primaryImageURL: URL?,
        fallbackImageURL: URL?,
        token: String,
        clientContext: PlexClientContext,
        isPaused: Bool,
        placeholderSymbol: String,
        imageClient: PlexImageClient = PlexImageClient()
    ) {
        self.primaryImageURL = primaryImageURL
        self.fallbackImageURL = fallbackImageURL
        self.token = token
        self.clientContext = clientContext
        self.isPaused = isPaused
        self.placeholderSymbol = placeholderSymbol
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

            if isPaused {
                pauseOverlay
            }
        }
        .frame(width: 88)
        .frame(maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.quaternary)
            .overlay {
                Image(systemName: placeholderSymbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
    }

    private var pauseOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.28))

            Image(systemName: "pause.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .padding(12)
                .background(.ultraThinMaterial, in: Circle())
        }
        .allowsHitTesting(false)
    }
}

private struct UserIdentityRow: View {
    let userName: String
    let playerName: String
    let thumb: String?
    let serverURL: URL?
    let serverToken: String
    let userToken: String
    let clientContext: PlexClientContext

    var body: some View {
        HStack(spacing: 10) {
            PlexAvatarView(
                thumb: thumb,
                serverURL: serverURL,
                serverToken: serverToken,
                userToken: userToken,
                clientContext: clientContext
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(userName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(playerName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
