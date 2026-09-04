import AppKit
import SwiftUI

struct PlexAudioPlayerOverlay: Equatable {
    let presentation: PlexAudioPlaybackPresentation
    let primaryImageURL: URL?
    let fallbackImageURL: URL?
    let token: String
    let clientContext: PlexClientContext

    init(
        presentation: PlexAudioPlaybackPresentation,
        serverURL: URL?,
        token: String,
        clientContext: PlexClientContext
    ) {
        self.presentation = presentation
        primaryImageURL = serverURL.flatMap { serverURL in
            PlexURLBuilder.mediaURL(
                serverURL: serverURL,
                path: presentation.artworkPaths.first
            )
        }
        fallbackImageURL = serverURL.flatMap { serverURL in
            PlexURLBuilder.mediaURL(
                serverURL: serverURL,
                path: presentation.artworkPaths.dropFirst().first
            )
        }
        self.token = token
        self.clientContext = clientContext
    }
}

struct PlexAudioPlayerStageContainer: View {
    let overlay: PlexAudioPlayerOverlay

    var body: some View {
        PlexAudioPlayerStage(overlay: overlay)
            .allowsHitTesting(false)
    }
}

@MainActor
final class PlexAudioPlayerStageHost {
    private(set) var hostingView: NSHostingView<PlexAudioPlayerStageContainer>?

    func update(in overlayView: NSView?, overlay: PlexAudioPlayerOverlay?) {
        guard let overlayView, let overlay else {
            remove()
            return
        }

        let hostingView: NSHostingView<PlexAudioPlayerStageContainer>
        if let existingHostingView = self.hostingView {
            hostingView = existingHostingView
            hostingView.rootView = PlexAudioPlayerStageContainer(overlay: overlay)
        } else {
            hostingView = NSHostingView(
                rootView: PlexAudioPlayerStageContainer(overlay: overlay)
            )
            hostingView.sizingOptions = []
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            self.hostingView = hostingView
        }

        guard hostingView.superview !== overlayView else {
            return
        }

        hostingView.removeFromSuperview()
        overlayView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: overlayView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: overlayView.bottomAnchor),
        ])
    }

    private func remove() {
        hostingView?.removeFromSuperview()
        hostingView = nil
    }
}

private struct PlexAudioPlayerStage: View {
    let overlay: PlexAudioPlayerOverlay
    @ScaledMetric(relativeTo: .largeTitle) private var artworkSize = 260.0
    @ScaledMetric(relativeTo: .title) private var compactArtworkSize = 200.0
    @ScaledMetric(relativeTo: .body) private var stageSpacing = 40.0
    @ScaledMetric(relativeTo: .body) private var stagePadding = 44.0
    @ScaledMetric(relativeTo: .body) private var controlsClearance = 72.0

    var body: some View {
        PlexArtworkBackdrop(
            primaryImageURL: overlay.primaryImageURL,
            fallbackImageURL: overlay.fallbackImageURL,
            token: overlay.token,
            clientContext: overlay.clientContext
        )
        .overlay {
            ViewThatFits(in: .horizontal) {
                horizontalContent
                compactContent
            }
            .padding(stagePadding)
            .padding(.bottom, controlsClearance)
        }
    }

    private var horizontalContent: some View {
        HStack(spacing: stageSpacing) {
            artwork(size: artworkSize)

            PlexAudioPlayerMetadata(
                presentation: overlay.presentation,
                alignment: .leading,
                textAlignment: .leading
            )
            .frame(minWidth: 220, maxWidth: 420, alignment: .leading)
        }
    }

    private var compactContent: some View {
        VStack(spacing: stageSpacing / 2) {
            artwork(size: compactArtworkSize)

            PlexAudioPlayerMetadata(
                presentation: overlay.presentation,
                alignment: .center,
                textAlignment: .center
            )
        }
    }

    private func artwork(size: CGFloat) -> some View {
        PlexArtworkView(
            primaryImageURL: overlay.primaryImageURL,
            fallbackImageURL: overlay.fallbackImageURL,
            token: overlay.token,
            clientContext: overlay.clientContext,
            placeholderSymbol: "music.note",
            width: size,
            height: size,
            cornerRadius: 18
        )
        .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
        .accessibilityHidden(true)
    }
}

private struct PlexAudioPlayerMetadata: View {
    let presentation: PlexAudioPlaybackPresentation
    let alignment: HorizontalAlignment
    let textAlignment: TextAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 8) {
            Text(presentation.title)
                .font(.largeTitle.bold())
                .lineLimit(2)

            ForEach(presentation.metadataLines, id: \.self) { line in
                Text(line)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .multilineTextAlignment(textAlignment)
        .accessibilityElement(children: .combine)
    }
}
