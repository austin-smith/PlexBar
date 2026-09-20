import SwiftUI

/// The shared cinematic treatment for Mac and Apple TV media pages.
/// Image loading belongs to the caller; this view owns only presentation.
public struct PlexCinematicBackdrop: View {
    public let image: Image?
    public let pageBackground: Color
    public var contentPlacement: ContentPlacement = .bottom

    public enum ContentPlacement {
        case bottom
        case leading
    }
    @Environment(\.colorSchemeContrast) private var contrast

    public var body: some View {
        ZStack {
            pageBackground

            if let image {
                fittedImage(image)

                if contentPlacement == .bottom {
                    fittedImage(image)
                        .blur(radius: 18, opaque: true)
                        .saturation(style.blurSaturation)
                        .overlay(Color.black.opacity(style.blurDarkeningOpacity))
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.34),
                                    .init(color: .white.opacity(0.18), location: 0.44),
                                    .init(color: .white.opacity(0.72), location: 0.58),
                                    .init(color: .white, location: 0.70),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                }
            }

            if contentPlacement == .leading {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(contrast == .increased ? 0.88 : 0.72), location: 0),
                        .init(color: .black.opacity(contrast == .increased ? 0.80 : 0.62), location: 0.36),
                        .init(color: .black.opacity(0.16), location: 0.67),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.20),
                        .init(color: .black.opacity(style.upperScrimOpacity), location: 0.40),
                        .init(color: .black.opacity(style.contentScrimOpacity), location: 0.62),
                        .init(color: .black.opacity(style.lowerScrimOpacity), location: 0.78),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.36),
                    .init(color: pageBackground.opacity(0.08), location: 0.50),
                    .init(color: pageBackground.opacity(0.34), location: 0.66),
                    .init(color: pageBackground.opacity(0.74), location: 0.82),
                    .init(color: pageBackground, location: 0.96),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func fittedImage(_ image: Image) -> some View {
        GeometryReader { geometry in
            image
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
    }

    private var style: PlexCinematicHeroStyle {
        PlexCinematicHeroStyle(contrast: contrast)
    }

    public init(image: Image? = nil, pageBackground: Color, contentPlacement: ContentPlacement = .bottom) {
        self.image = image
        self.pageBackground = pageBackground
        self.contentPlacement = contentPlacement
    }
}

public struct PlexCinematicHeroStyle: Equatable {
    public let blurSaturation: Double
    public let blurDarkeningOpacity: Double
    public let upperScrimOpacity: Double
    public let contentScrimOpacity: Double
    public let lowerScrimOpacity: Double

    public init(contrast: ColorSchemeContrast) {
        let usesIncreasedContrast = contrast == .increased
        blurSaturation = usesIncreasedContrast ? 0.56 : 0.78
        blurDarkeningOpacity = usesIncreasedContrast ? 0.64 : 0.48
        upperScrimOpacity = usesIncreasedContrast ? 0.28 : 0.16
        contentScrimOpacity = usesIncreasedContrast ? 0.72 : 0.56
        lowerScrimOpacity = usesIncreasedContrast ? 0.56 : 0.40
    }
}
