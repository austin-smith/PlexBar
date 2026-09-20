import PlexClientKit
import SwiftUI

struct PlexCinematicHero<Content: View>: View {
    let primaryImageURL: URL?
    let fallbackImageURL: URL?
    let token: String
    let clientContext: PlexClientContext
    let placeholderSymbol: String
    private let content: Content
    private let pageBackground = Color(nsColor: .windowBackgroundColor)
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var artwork: PlexArtworkPresentationState

    init(
        primaryImageURL: URL?,
        fallbackImageURL: URL? = nil,
        token: String,
        clientContext: PlexClientContext,
        placeholderSymbol: String,
        @ViewBuilder content: () -> Content
    ) {
        self.primaryImageURL = primaryImageURL
        self.fallbackImageURL = fallbackImageURL
        self.token = token
        self.clientContext = clientContext
        self.placeholderSymbol = placeholderSymbol
        self.content = content()
        _artwork = State(initialValue: PlexArtworkPresentationState(
            primaryImageURL: primaryImageURL,
            fallbackImageURL: fallbackImageURL,
            token: token,
            wantsPalette: false,
            maximumPixelSize: 2_400
        ))
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PlexCinematicBackdrop(image: artwork.image, pageBackground: pageBackground)

            if artwork.image == nil {
                placeholder
            }

            content
                .padding(.horizontal, 32)
                .padding(.bottom, 44)
        }
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical, alignment: .top) { availableHeight, _ in
            min(
                max(
                    availableHeight * PlexCinematicHeroMetrics.viewportHeightFraction,
                    PlexCinematicHeroMetrics.minimumHeight
                ),
                PlexCinematicHeroMetrics.maximumHeight
            )
        }
        .animation(
            accessibilityReduceMotion ? nil : .easeOut(duration: 0.24),
            value: artwork.cgImage != nil
        )
        .task(id: requestKey) {
            await artwork.load(
                primaryImageURL: primaryImageURL,
                fallbackImageURL: fallbackImageURL,
                token: token,
                clientContext: clientContext,
                wantsPalette: false,
                maximumPixelSize: 2_400
            )
        }
        .accessibilityElement(children: .contain)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.76),
                    Color.black.opacity(0.18),
                    Color.clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: placeholderSymbol)
                .font(.system(size: 76, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.24))

            if artwork.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                    .offset(y: 62)
            }
        }
        .accessibilityHidden(true)
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

}

private struct PlexCinematicPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.capsule)
    }
}

private struct PlexCinematicUtilityButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.circle)
    }
}

extension View {
    func plexCinematicPrimaryButton() -> some View {
        buttonStyle(PlexCinematicPrimaryButtonStyle())
            .frame(height: 44)
            .contentShape(Capsule())
            .glassEffect(
                .regular.tint(.white.opacity(0.62)).interactive(),
                in: .capsule
            )
            .foregroundStyle(.black.opacity(0.86))
    }

    func plexCinematicUtilityButton() -> some View {
        buttonStyle(PlexCinematicUtilityButtonStyle())
            .font(.system(size: 16, weight: .medium))
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: .circle)
    }
}
