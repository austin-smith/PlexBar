import PlexModels
import SwiftUI

enum PlexVideoPreparationPolicy {
    static func shouldPresent(
        mediaKind: PlexPlaybackMediaKind,
        status: PlexPlaybackStatus,
        isLoading: Bool
    ) -> Bool {
        guard mediaKind == .video else {
            return false
        }

        switch status {
        case .idle:
            return isLoading
        case .preparing:
            return true
        case .playing, .paused, .buffering, .ended, .failed:
            return false
        }
    }

}

struct PlexVideoPreparationStage: View {
    let title: String
    let primaryImageURL: URL?
    let fallbackImageURL: URL?
    let token: String
    let clientContext: PlexClientContext

    init(
        item: PlexMediaItem,
        serverURL: URL?,
        token: String,
        clientContext: PlexClientContext
    ) {
        title = item.title
        let artworkPaths = item.nowPlayingArtworkPaths
        primaryImageURL = serverURL.flatMap { serverURL in
            PlexURLBuilder.mediaURL(serverURL: serverURL, path: artworkPaths.first)
        }
        fallbackImageURL = serverURL.flatMap { serverURL in
            PlexURLBuilder.mediaURL(
                serverURL: serverURL,
                path: artworkPaths.dropFirst().first
            )
        }
        self.token = token
        self.clientContext = clientContext
    }

    var body: some View {
        ZStack {
            PlexArtworkBackdrop(
                primaryImageURL: primaryImageURL,
                fallbackImageURL: fallbackImageURL,
                token: token,
                clientContext: clientContext
            )

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)

                Text(title)
                    .font(.title2.bold())
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text("Preparing…")
                    .foregroundStyle(.secondary)
            }
            .scenePadding()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preparing \(title)")
        }
        .allowsHitTesting(false)
    }
}
