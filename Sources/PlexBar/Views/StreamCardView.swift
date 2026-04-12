import AppKit
import SwiftUI

struct StreamCardView: View {
    let session: PlexSession
    let settingsStore: PlexSettingsStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PosterThumbnailView(
                primaryImageURL: posterURL,
                fallbackImageURL: transcodedPosterURL,
                clientIdentifier: settingsStore.clientIdentifier,
                token: settingsStore.trimmedServerToken,
                isPaused: session.isPaused
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
                        imageURL: userAvatarURL,
                        token: userAvatarToken,
                        clientIdentifier: settingsStore.clientIdentifier
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var posterURL: URL? {
        guard let serverURL = settingsStore.normalizedServerURL else {
            return nil
        }

        return PlexURLBuilder.authenticatedURL(
            serverURL: serverURL,
            path: session.posterPath,
            token: settingsStore.trimmedServerToken
        )
    }

    private var transcodedPosterURL: URL? {
        guard let serverURL = settingsStore.normalizedServerURL else {
            return nil
        }

        return PlexURLBuilder.transcodedArtworkURL(
            serverURL: serverURL,
            path: session.posterPath,
            token: settingsStore.trimmedServerToken,
            width: 176,
            height: 264
        )
    }

    private var userAvatarURL: URL? {
        guard let thumb = session.user?.thumb?.nilIfBlank else {
            return nil
        }

        if let absoluteURL = URL(string: thumb), absoluteURL.scheme != nil {
            return absoluteURL
        }

        guard let serverURL = settingsStore.normalizedServerURL else {
            return nil
        }

        return PlexURLBuilder.authenticatedURL(
            serverURL: serverURL,
            path: thumb,
            token: settingsStore.trimmedServerToken
        )
    }

    private var userAvatarToken: String {
        guard let imageURL = userAvatarURL, let host = imageURL.host?.lowercased() else {
            return settingsStore.trimmedServerToken
        }

        if host.contains("plex.tv") {
            return settingsStore.trimmedUserToken
        }

        return settingsStore.trimmedServerToken
    }
}

private struct PosterThumbnailView: View {
    let primaryImageURL: URL?
    let fallbackImageURL: URL?
    let clientIdentifier: String
    let token: String
    let isPaused: Bool

    @State private var image: Image?
    @State private var isLoading = false

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
            clientIdentifier,
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

        isLoading = true
        image = nil

        for url in candidateURLs {
            if Task.isCancelled {
                isLoading = false
                return
            }

            do {
                if let loadedImage = try await fetchImage(from: url) {
                    image = Image(nsImage: loadedImage)
                    isLoading = false
                    return
                }
            } catch {
                continue
            }
        }

        isLoading = false
    }

    private func fetchImage(from url: URL) async throws -> NSImage? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.addValue("image/*", forHTTPHeaderField: "Accept")
        request.addValue(token, forHTTPHeaderField: "X-Plex-Token")
        request.addValue(clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(AppConstants.appName, forHTTPHeaderField: "X-Plex-Product")
        request.addValue(AppConstants.productVersion, forHTTPHeaderField: "X-Plex-Version")
        request.addValue("macOS", forHTTPHeaderField: "X-Plex-Platform")
        request.addValue("Mac", forHTTPHeaderField: "X-Plex-Device")
        request.addValue("Mac (\(AppConstants.appName))", forHTTPHeaderField: "X-Plex-Device-Name")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            return nil
        }

        return NSImage(data: data)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.quaternary)
            .overlay {
                Image(systemName: "tv")
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
    let imageURL: URL?
    let token: String
    let clientIdentifier: String

    var body: some View {
        HStack(spacing: 10) {
            UserAvatarView(
                imageURL: imageURL,
                token: token,
                clientIdentifier: clientIdentifier
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

private struct UserAvatarView: View {
    let imageURL: URL?
    let token: String
    let clientIdentifier: String

    @State private var image: Image?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(.quaternary)
                    .overlay {
                        if isLoading {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "person.fill")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(Circle())
        .task(id: requestKey) {
            await loadImage()
        }
    }

    private var requestKey: String {
        [imageURL?.absoluteString, token, clientIdentifier]
            .compactMap { $0 }
            .joined(separator: "|")
    }

    @MainActor
    private func loadImage() async {
        guard let imageURL else {
            image = nil
            isLoading = false
            return
        }

        isLoading = true
        image = nil

        do {
            if let loadedImage = try await fetchImage(from: imageURL) {
                image = Image(nsImage: loadedImage)
            }
        } catch {
            image = nil
        }

        isLoading = false
    }

    private func fetchImage(from url: URL) async throws -> NSImage? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.addValue("image/*", forHTTPHeaderField: "Accept")

        if !token.isEmpty {
            request.addValue(token, forHTTPHeaderField: "X-Plex-Token")
        }

        request.addValue(clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.addValue(AppConstants.appName, forHTTPHeaderField: "X-Plex-Product")
        request.addValue(AppConstants.productVersion, forHTTPHeaderField: "X-Plex-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            return nil
        }

        return NSImage(data: data)
    }
}
