import SwiftUI
import UIKit

struct TVAudioPlayerStageContainer: View {
    let store: TVAppStore
    let presentation: PlexAudioPlaybackPresentation

    var body: some View {
        TVAudioPlayerStage(presentation: presentation)
            .environment(store)
            .allowsHitTesting(false)
    }
}

@MainActor
final class TVAudioPlayerStageHost {
    private var hostingController: UIHostingController<TVAudioPlayerStageContainer>?
    private var presentation: PlexAudioPlaybackPresentation?

    func update(
        in overlayView: UIView?,
        store: TVAppStore,
        presentation: PlexAudioPlaybackPresentation?
    ) {
        guard let overlayView, let presentation else {
            remove()
            return
        }

        let hostingController: UIHostingController<TVAudioPlayerStageContainer>
        if let existingHostingController = self.hostingController {
            hostingController = existingHostingController
            if presentation != self.presentation {
                hostingController.rootView = TVAudioPlayerStageContainer(
                    store: store,
                    presentation: presentation
                )
            }
        } else {
            hostingController = UIHostingController(
                rootView: TVAudioPlayerStageContainer(
                    store: store,
                    presentation: presentation
                )
            )
            hostingController.view.backgroundColor = .clear
            hostingController.view.isUserInteractionEnabled = false
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            self.hostingController = hostingController
        }
        self.presentation = presentation

        guard hostingController.view.superview !== overlayView else { return }

        hostingController.view.removeFromSuperview()
        overlayView.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: overlayView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: overlayView.bottomAnchor),
        ])
    }

    func remove() {
        hostingController?.view.removeFromSuperview()
        hostingController = nil
        presentation = nil
    }
}

private struct TVAudioPlayerStage: View {
    let presentation: PlexAudioPlaybackPresentation

    var body: some View {
        ZStack {
            backdrop

            HStack(spacing: 60) {
                artwork

                VStack(alignment: .leading, spacing: 16) {
                    Text("NOW PLAYING")
                        .font(TVTypography.cardTitle)
                        .tracking(2.4)
                        .foregroundStyle(TVTheme.plexGold)

                    Text(presentation.title)
                        .font(TVTypography.title)
                        .lineLimit(3)

                    ForEach(presentation.metadataLines, id: \.self) { line in
                        Text(line)
                            .font(TVTypography.sectionTitle)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .safeAreaPadding(.horizontal)
            .safeAreaPadding(.bottom, 160)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var artworkPath: String? {
        presentation.artworkPaths.first
    }

    private var backdrop: some View {
        TVPlexArtwork(
            path: artworkPath,
            width: 1_920,
            height: 1_080,
            systemImage: "music.note"
        )
        .blur(radius: 72)
        .scaleEffect(1.18)
        .overlay {
            LinearGradient(
                colors: [
                    .black.opacity(0.28),
                    .black.opacity(0.72),
                    .black.opacity(0.94),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipped()
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var artwork: some View {
        TVPlexArtwork(
            path: artworkPath,
            width: 900,
            height: 900,
            systemImage: "music.note"
        )
        .aspectRatio(1, contentMode: .fit)
        .containerRelativeFrame(.horizontal, count: 4, spacing: TVLayout.cardSpacing)
        .clipShape(.rect(cornerRadius: 12))
        .accessibilityHidden(true)
    }

    private var accessibilityLabel: String {
        ([presentation.title] + presentation.metadataLines).joined(separator: ", ")
    }
}
