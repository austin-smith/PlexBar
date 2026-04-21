import SwiftUI

struct StreamCardView: View {
    let session: PlexSession
    let serverURL: URL?
    let settingsStore: PlexSettingsStore
    let snapshotDate: Date?
    let resolvedLocation: String?
    @State private var artwork: PlexArtworkPresentationState

    init(
        session: PlexSession,
        serverURL: URL?,
        settingsStore: PlexSettingsStore,
        snapshotDate: Date?,
        resolvedLocation: String?
    ) {
        self.session = session
        self.serverURL = serverURL
        self.settingsStore = settingsStore
        self.snapshotDate = snapshotDate
        self.resolvedLocation = resolvedLocation

        let posterURL = Self.posterURL(serverURL: serverURL, posterPath: session.posterPath)
        let transcodedPosterURL = Self.transcodedPosterURL(serverURL: serverURL, posterPath: session.posterPath)
        _artwork = State(initialValue: PlexArtworkPresentationState(
            primaryImageURL: posterURL,
            fallbackImageURL: transcodedPosterURL,
            token: settingsStore.trimmedServerToken,
            wantsPalette: true
        ))
    }

    private var clientContext: PlexClientContext {
        PlexClientContext(clientIdentifier: settingsStore.clientIdentifier)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PosterThumbnailView(
                artwork: artwork,
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

                    if let playbackTimingSummary {
                        Text(playbackTimingSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
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
                        resolvedLocation: resolvedLocation,
                        thumb: session.user?.thumb,
                        serverURL: serverURL,
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
        .background {
            StreamCardBackground(palette: artwork.palette)
        }
        .task(id: requestKey) {
            await artwork.load(
                primaryImageURL: posterURL,
                fallbackImageURL: transcodedPosterURL,
                token: settingsStore.trimmedServerToken,
                clientContext: clientContext,
                wantsPalette: true
            )
        }
    }

    private var playbackTimingSummary: String? {
        guard let snapshotDate else {
            return nil
        }

        return session.playbackTimingSummary(referenceDate: snapshotDate)
    }

    private var posterURL: URL? {
        Self.posterURL(serverURL: serverURL, posterPath: session.posterPath)
    }

    private var transcodedPosterURL: URL? {
        Self.transcodedPosterURL(serverURL: serverURL, posterPath: session.posterPath)
    }

    private var requestKey: String {
        [
            posterURL?.absoluteString,
            transcodedPosterURL?.absoluteString,
            clientContext.clientIdentifier,
            settingsStore.trimmedServerToken,
        ]
        .compactMap { $0 }
        .joined(separator: "|")
    }

    private static func posterURL(serverURL: URL?, posterPath: String?) -> URL? {
        guard let serverURL else {
            return nil
        }

        return PlexURLBuilder.mediaURL(
            serverURL: serverURL,
            path: posterPath
        )
    }

    private static func transcodedPosterURL(serverURL: URL?, posterPath: String?) -> URL? {
        guard let serverURL else {
            return nil
        }

        return PlexURLBuilder.transcodedArtworkURL(
            serverURL: serverURL,
            path: posterPath,
            width: 176,
            height: 264
        )
    }

}

private struct PosterThumbnailView: View {
    @Bindable var artwork: PlexArtworkPresentationState
    let isPaused: Bool
    let placeholderSymbol: String

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

            if isPaused {
                pauseOverlay
            }
        }
        .frame(width: 88)
        .frame(maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

            PauseGlassBadge(
                font: .system(size: 20, weight: .semibold),
                size: 44
            )
        }
        .allowsHitTesting(false)
    }
}

struct PauseGlassBadge: View {
    let font: Font
    let size: CGFloat

    var body: some View {
        Image(systemName: "pause.fill")
            .font(font)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(Color.white.opacity(0.08))
            }
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
            }
    }
}

private struct StreamCardBackground: View {
    let palette: PlexArtworkPalette?

    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        shape
            .fill(baseBackground)
            .overlay {
                if let palette {
                    MeshGradient(
                        width: 2,
                        height: 2,
                        points: [
                            SIMD2<Float>(0, 0),
                            SIMD2<Float>(1, 0),
                            SIMD2<Float>(0, 1),
                            SIMD2<Float>(1, 1),
                        ],
                        colors: palette.swiftUIColors
                    )
                    .opacity(0.92)
                    .clipShape(shape)
                }
            }
            .overlay {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.06),
                        Color.black.opacity(0.08),
                        Color.black.opacity(0.28),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(shape)
            }
            .overlay {
                shape.strokeBorder(.white.opacity(0.08))
            }
    }

    private var baseBackground: AnyShapeStyle {
        if palette == nil {
            return AnyShapeStyle(.quaternary.opacity(0.3))
        }

        return AnyShapeStyle(Color.black.opacity(0.22))
    }
}

private struct UserIdentityRow: View {
    let userName: String
    let playerName: String
    let resolvedLocation: String?
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

                if let resolvedLocation {
                    Text(resolvedLocation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
