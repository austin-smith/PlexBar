import SwiftUI

private struct StreamCardTheme {
    let baseBackground: AnyShapeStyle
    let meshOpacity: Double
    let contentReadabilityGradient: Gradient?
    let showsBorder: Bool

    static func make(for colorScheme: ColorScheme, hasPalette: Bool) -> StreamCardTheme {
        switch colorScheme {
        case .light:
            return StreamCardTheme(
                baseBackground: AnyShapeStyle(.quaternary.opacity(0.3)),
                meshOpacity: 0,
                contentReadabilityGradient: nil,
                showsBorder: false
            )
        case .dark:
            return StreamCardTheme(
                baseBackground: hasPalette
                    ? AnyShapeStyle(Color.black.opacity(0.22))
                    : AnyShapeStyle(.quaternary.opacity(0.3)),
                meshOpacity: hasPalette ? 0.92 : 0,
                contentReadabilityGradient: Gradient(stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .clear, location: 0.22),
                    .init(color: Color.black.opacity(0.12), location: 0.56),
                    .init(color: Color.black.opacity(0.30), location: 1.0),
                ]),
                showsBorder: true
            )
        @unknown default:
            return make(for: .dark, hasPalette: hasPalette)
        }
    }
}

struct StreamCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let session: PlexSession
    let sessionStore: PlexSessionStore
    let onRequestTerminate: (PlexSession) -> Void
    let isShowingTerminatePrompt: Bool
    @Binding var terminateMessage: String
    let onCancelTerminate: () -> Void
    let onConfirmTerminate: (PlexSession) -> Void
    let serverURL: URL?
    let settingsStore: PlexSettingsStore
    let snapshotDate: Date?
    let resolvedLocation: String?
    @State private var artwork: PlexArtworkPresentationState
    @State private var isShowingActionsPopover = false

    init(
        session: PlexSession,
        sessionStore: PlexSessionStore,
        onRequestTerminate: @escaping (PlexSession) -> Void,
        isShowingTerminatePrompt: Bool,
        terminateMessage: Binding<String>,
        onCancelTerminate: @escaping () -> Void,
        onConfirmTerminate: @escaping (PlexSession) -> Void,
        serverURL: URL?,
        settingsStore: PlexSettingsStore,
        snapshotDate: Date?,
        resolvedLocation: String?
    ) {
        self.session = session
        self.sessionStore = sessionStore
        self.onRequestTerminate = onRequestTerminate
        self.isShowingTerminatePrompt = isShowingTerminatePrompt
        self._terminateMessage = terminateMessage
        self.onCancelTerminate = onCancelTerminate
        self.onConfirmTerminate = onConfirmTerminate
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
        let theme = StreamCardTheme.make(for: colorScheme, hasPalette: artwork.palette != nil)
        let isTerminating = sessionStore.isTerminating(session)
        defaultCardContent(isTerminating: isTerminating)
        .opacity(isShowingTerminatePrompt ? 0.38 : 1)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background {
            StreamCardBackground(palette: artwork.palette, theme: theme)
        }
        .overlay {
            if isShowingTerminatePrompt {
                terminatePromptOverlay
            } else if isTerminating {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.black.opacity(colorScheme == .dark ? 0.34 : 0.12))
                    .overlay {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)

                            Text("Stopping playback…")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.regularMaterial, in: Capsule())
                    }
                    .allowsHitTesting(false)
            }
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

    @ViewBuilder
    private func defaultCardContent(isTerminating: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            PosterThumbnailView(
                artwork: artwork,
                isPaused: session.isPaused,
                placeholderSymbol: session.contentKind.contentMetaSymbolName
            )

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.headline)
                        .font(.headline)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 36)
                        .overlay(alignment: .trailing) {
                            actionsButton(isTerminating: isTerminating)
                        }

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

                VStack(alignment: .leading, spacing: 6) {
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
    }

    private func actionsButton(isTerminating: Bool) -> some View {
        Button {
            isShowingActionsPopover.toggle()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isTerminating || isShowingTerminatePrompt)
        .popover(isPresented: $isShowingActionsPopover, arrowEdge: .top) {
            SessionActionsPopover {
                isShowingActionsPopover = false
                onRequestTerminate(session)
            }
        }
    }

    private var terminatePromptOverlay: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.black.opacity(colorScheme == .dark ? 0.08 : 0.02))
            .overlay {
                GlassEffectContainer(spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Stop Playback")
                            .font(.headline)

                        Text("\(session.userDisplayName) • \(session.headline)")
                            .font(.footnote.weight(.medium))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)

                        TextField("Optional message to user", text: $terminateMessage)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(0.01))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(.white.opacity(0.06), lineWidth: 0.8)
                                    }
                            }
                            .glassEffect(.regular.tint(.white.opacity(0.02)).interactive(), in: .rect(cornerRadius: 12))

                        HStack(spacing: 8) {
                            Spacer()

                            Button("Cancel") {
                                onCancelTerminate()
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .keyboardShortcut(.cancelAction)

                            Button("Stop", role: .destructive) {
                                onConfirmTerminate(session)
                            }
                            .buttonStyle(.glassProminent)
                            .controlSize(.small)
                            .keyboardShortcut(.defaultAction)
                            }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(colorScheme == .dark ? 0.04 : 0.12),
                                        Color.white.opacity(colorScheme == .dark ? 0.008 : 0.03),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(colorScheme == .dark ? 0.08 : 0.12), lineWidth: 0.8)
                    }
                    .glassEffect(.regular.tint(.white.opacity(0.02)), in: .rect(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)
            }
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

private struct SessionActionsPopover: View {
    let onRequestTerminate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(role: .destructive) {
                onRequestTerminate()
            } label: {
                Label("Stop Playback…", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 220, alignment: .leading)
    }
}

private struct PosterThumbnailView: View {
    @Bindable var artwork: PlexArtworkPresentationState
    let isPaused: Bool
    let placeholderSymbol: String
    private let posterWidth: CGFloat = 88
    private let posterAspectRatio: CGFloat = 2 / 3

    private var posterHeight: CGFloat {
        posterWidth / posterAspectRatio
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

            if isPaused {
                pauseOverlay
            }
        }
        .frame(width: posterWidth, height: posterHeight)
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
    let theme: StreamCardTheme

    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        shape
            .fill(theme.baseBackground)
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
                    .opacity(theme.meshOpacity)
                    .clipShape(shape)
                }
            }
            .overlay {
                if let gradient = theme.contentReadabilityGradient {
                    LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing)
                        .clipShape(shape)
                }
            }
            .overlay {
                if theme.showsBorder {
                    shape.strokeBorder(.white.opacity(0.08))
                }
            }
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
