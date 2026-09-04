import AppKit
import SwiftUI

struct PlexArtworkBackdrop: View {
    let primaryImageURL: URL?
    let fallbackImageURL: URL?
    let token: String
    let clientContext: PlexClientContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var artwork: PlexArtworkPresentationState

    init(
        primaryImageURL: URL?,
        fallbackImageURL: URL? = nil,
        token: String,
        clientContext: PlexClientContext
    ) {
        self.primaryImageURL = primaryImageURL
        self.fallbackImageURL = fallbackImageURL
        self.token = token
        self.clientContext = clientContext
        _artwork = State(initialValue: PlexArtworkPresentationState(
            primaryImageURL: primaryImageURL,
            fallbackImageURL: fallbackImageURL,
            token: token,
            wantsPalette: true,
            maximumPixelSize: 160
        ))
    }

    var body: some View {
        ZStack {
            windowBackground

            if let palette = artwork.palette {
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
                .opacity(style.paletteOpacity)

                LinearGradient(
                    colors: [
                        windowBackground.opacity(style.topFadeOpacity),
                        windowBackground.opacity(style.middleFadeOpacity),
                        windowBackground.opacity(style.bottomFadeOpacity),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .animation(
            accessibilityReduceMotion ? nil : .easeOut(duration: 0.28),
            value: artwork.palette
        )
        .task(id: requestKey) {
            await artwork.load(
                primaryImageURL: primaryImageURL,
                fallbackImageURL: fallbackImageURL,
                token: token,
                clientContext: clientContext,
                wantsPalette: true,
                maximumPixelSize: 160
            )
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var windowBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    private var style: PlexArtworkBackdropStyle {
        PlexArtworkBackdropStyle(
            colorScheme: colorScheme,
            contrast: colorSchemeContrast
        )
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

struct PlexArtworkBackdropStyle: Equatable {
    let paletteOpacity: Double
    let topFadeOpacity: Double
    let middleFadeOpacity: Double
    let bottomFadeOpacity: Double

    init(colorScheme: ColorScheme, contrast: ColorSchemeContrast) {
        let usesIncreasedContrast = contrast == .increased
        switch colorScheme {
        case .dark:
            paletteOpacity = usesIncreasedContrast ? 0.50 : 0.72
            topFadeOpacity = usesIncreasedContrast ? 0.34 : 0.10
            middleFadeOpacity = usesIncreasedContrast ? 0.70 : 0.50
        case .light:
            paletteOpacity = usesIncreasedContrast ? 0.20 : 0.34
            topFadeOpacity = usesIncreasedContrast ? 0.46 : 0.24
            middleFadeOpacity = usesIncreasedContrast ? 0.80 : 0.66
        @unknown default:
            paletteOpacity = usesIncreasedContrast ? 0.20 : 0.34
            topFadeOpacity = usesIncreasedContrast ? 0.46 : 0.24
            middleFadeOpacity = usesIncreasedContrast ? 0.80 : 0.66
        }
        bottomFadeOpacity = usesIncreasedContrast ? 1.0 : 0.96
    }
}
