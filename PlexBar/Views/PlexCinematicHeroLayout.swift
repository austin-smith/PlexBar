import PlexClientKit
import PlexModels
import SwiftUI

enum PlexCinematicHeroMetrics {
    static let viewportHeightFraction: CGFloat = 0.68
    static let minimumHeight: CGFloat = 600
    static let maximumHeight: CGFloat = 780
    static let primaryColumnWidth: CGFloat = 320
    static let columnSpacing: CGFloat = 32
    static let secondaryColumnMaximumWidth: CGFloat = 590
    static let logoHeight: CGFloat = 98
}

struct PlexCinematicHeroLayout<Primary: View, Secondary: View>: View {
    private let primary: Primary
    private let secondary: Secondary

    init(
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: PlexCinematicHeroMetrics.columnSpacing) {
            primary
                .frame(
                    width: PlexCinematicHeroMetrics.primaryColumnWidth,
                    alignment: .leading
                )

            secondary
                .frame(
                    maxWidth: PlexCinematicHeroMetrics.secondaryColumnMaximumWidth,
                    alignment: .leading
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PlexCinematicMediaHero<Actions: View, Details: View>: View {
    let primaryImageURL: URL?
    let fallbackImageURL: URL?
    let clearLogoURL: URL?
    let title: String
    let logoAccessibilityLabel: String?
    let token: String
    let clientContext: PlexClientContext
    let placeholderSymbol: String
    let playbackTitle: String?
    let ratingsItem: PlexMediaItem
    let hasResumePosition: Bool
    let resumeProgress: Double?
    let isPreparingPlayback: Bool
    let isPlaybackEnabled: Bool
    let preparePlayback: (PlexPlaybackStartOption) -> Void
    private let actions: Actions
    private let details: Details

    init(
        primaryImageURL: URL?,
        fallbackImageURL: URL?,
        clearLogoURL: URL?,
        title: String,
        logoAccessibilityLabel: String? = nil,
        token: String,
        clientContext: PlexClientContext,
        placeholderSymbol: String,
        playbackTitle: String?,
        ratingsItem: PlexMediaItem,
        hasResumePosition: Bool,
        resumeProgress: Double?,
        isPreparingPlayback: Bool,
        isPlaybackEnabled: Bool,
        preparePlayback: @escaping (PlexPlaybackStartOption) -> Void,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder details: () -> Details
    ) {
        self.primaryImageURL = primaryImageURL
        self.fallbackImageURL = fallbackImageURL
        self.clearLogoURL = clearLogoURL
        self.title = title
        self.logoAccessibilityLabel = logoAccessibilityLabel
        self.token = token
        self.clientContext = clientContext
        self.placeholderSymbol = placeholderSymbol
        self.playbackTitle = playbackTitle
        self.ratingsItem = ratingsItem
        self.hasResumePosition = hasResumePosition
        self.resumeProgress = resumeProgress
        self.isPreparingPlayback = isPreparingPlayback
        self.isPlaybackEnabled = isPlaybackEnabled
        self.preparePlayback = preparePlayback
        self.actions = actions()
        self.details = details()
    }

    var body: some View {
        PlexCinematicHero(
            primaryImageURL: primaryImageURL,
            fallbackImageURL: fallbackImageURL,
            token: token,
            clientContext: clientContext,
            placeholderSymbol: placeholderSymbol
        ) {
            PlexCinematicHeroLayout {
                VStack(alignment: .leading, spacing: 18) {
                    PlexMediaLogoView(
                        imageURL: clearLogoURL,
                        fallbackTitle: title,
                        accessibilityLabel: logoAccessibilityLabel,
                        token: token,
                        clientContext: clientContext,
                        maximumWidth: PlexCinematicHeroMetrics.primaryColumnWidth,
                        maximumHeight: PlexCinematicHeroMetrics.logoHeight
                    )
                    .accessibilityAddTraits(.isHeader)

                    if let playbackTitle {
                        PlexPlaybackStartControl(
                            title: playbackTitle,
                            hasResumePosition: hasResumePosition,
                            resumeProgress: resumeProgress,
                            isPreparing: isPreparingPlayback,
                            isEnabled: isPlaybackEnabled,
                            width: PlexCinematicHeroMetrics.primaryColumnWidth,
                            action: preparePlayback
                        )
                    }

                    actions
                }
            } secondary: {
                VStack(alignment: .leading, spacing: 12) {
                    details
                    PlexExternalRatingsView(item: ratingsItem)
                }
            }
        }
        .foregroundStyle(.white)
    }
}
