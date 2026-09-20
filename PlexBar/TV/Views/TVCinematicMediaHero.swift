import PlexClientKit
import PlexModels
import SwiftUI

/// A single reading column leaves the right side of the artwork unobstructed.
struct TVCinematicMediaHero<Actions: View>: View {
    let item: PlexMediaItem
    let showSummary: () -> Void
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            identity

            if let episodeTitle = item.tvEpisodeTitle {
                Text(episodeTitle)
                    .font(TVTypography.sectionTitle)
                    .lineLimit(2)
            }

            metadata
            PlexExternalRatingsView(item: item, valueFont: TVTypography.metadata)

            if let summary = item.summary?.nilIfBlank {
                Button(action: showSummary) {
                    Text(summary)
                        .font(TVTypography.body)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .buttonStyle(.plain)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .padding(.horizontal, -12)
                .padding(.top, 8)
                .accessibilityIdentifier("detail-summary")
                .accessibilityHint("Select to read the full synopsis.")
            }

            actions
                .padding(.top, 8)
        }
        .frame(width: 680, alignment: .leading)
        .padding(.top, 40)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .safeAreaPadding(.horizontal)
        .focusSection()
    }

    private var identity: some View {
        TVArtworkImage(path: item.clearLogoPath, width: 880, height: 280, usesOriginalImage: true) { image in
            ZStack(alignment: .leading) {
                if let image {
                    image.resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } else {
                    Text(item.contextTitle ?? item.title)
                        .font(TVTypography.title)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: 320, height: 90, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.contextTitle ?? item.title)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var metadata: some View {
        if let facts = PlexMediaSummaryPresentation(item: item).detailFacts {
            Text(facts)
                .font(TVTypography.metadata)
                .foregroundStyle(.white.opacity(0.84))
                .lineLimit(2)
        }
        if let genres = PlexMediaSummaryPresentation(item: item).genres {
            Text(genres)
                .font(TVTypography.metadata)
                .foregroundStyle(.white.opacity(0.84))
                .lineLimit(2)
        }
    }
}
