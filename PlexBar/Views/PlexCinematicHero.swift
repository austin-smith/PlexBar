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
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
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
            pageBackground

            if let image = artwork.image {
                GeometryReader { geometry in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
                .transition(.opacity)
            } else {
                placeholder
            }

            if let image = artwork.image {
                GeometryReader { geometry in
                    ZStack {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .blur(radius: 18, opaque: true)
                            .saturation(style.blurSaturation)

                        Color.black.opacity(style.blurDarkeningOpacity)
                    }
                }
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.34),
                            .init(color: .white.opacity(0.18), location: 0.44),
                            .init(color: .white.opacity(0.72), location: 0.58),
                            .init(color: .white, location: 0.70),
                            .init(color: .white, location: 1.00),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .allowsHitTesting(false)
            }

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.20),
                    .init(color: .black.opacity(style.upperScrimOpacity), location: 0.40),
                    .init(color: .black.opacity(style.contentScrimOpacity), location: 0.62),
                    .init(color: .black.opacity(style.lowerScrimOpacity), location: 0.78),
                    .init(color: .black.opacity(style.lowerScrimOpacity), location: 1.00),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.36),
                    .init(color: pageBackground.opacity(0.08), location: 0.50),
                    .init(color: pageBackground.opacity(0.34), location: 0.66),
                    .init(color: pageBackground.opacity(0.74), location: 0.82),
                    .init(color: pageBackground, location: 0.96),
                    .init(color: pageBackground, location: 1.00),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

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

    private var style: PlexCinematicHeroStyle {
        PlexCinematicHeroStyle(contrast: colorSchemeContrast)
    }
}

struct PlexCinematicHeroStyle: Equatable {
    let blurSaturation: Double
    let blurDarkeningOpacity: Double
    let upperScrimOpacity: Double
    let contentScrimOpacity: Double
    let lowerScrimOpacity: Double

    init(contrast: ColorSchemeContrast) {
        let usesIncreasedContrast = contrast == .increased
        blurSaturation = usesIncreasedContrast ? 0.56 : 0.78
        blurDarkeningOpacity = usesIncreasedContrast ? 0.64 : 0.48
        upperScrimOpacity = usesIncreasedContrast ? 0.28 : 0.16
        contentScrimOpacity = usesIncreasedContrast ? 0.72 : 0.56
        lowerScrimOpacity = usesIncreasedContrast ? 0.56 : 0.40
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
