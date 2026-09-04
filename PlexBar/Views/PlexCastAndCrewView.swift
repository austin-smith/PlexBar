import SwiftUI

struct PlexCastAndCrewView: View {
    let item: PlexMediaItem
    let episodeSeriesCast: [PlexTag]
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @ScaledMetric(relativeTo: .subheadline) private var portraitSize: CGFloat = 88

    init(
        item: PlexMediaItem,
        episodeSeriesCast: [PlexTag] = [],
        settingsStore: PlexSettingsStore,
        connectionStore: PlexConnectionStore
    ) {
        self.item = item
        self.episodeSeriesCast = episodeSeriesCast
        self.settingsStore = settingsStore
        self.connectionStore = connectionStore
    }

    private var presentation: PlexCastAndCrewPresentation {
        PlexCastAndCrewPresentation(
            item: item,
            episodeSeriesCast: episodeSeriesCast
        )
    }

    var body: some View {
        if !presentation.isEmpty {
            VStack(alignment: .leading, spacing: 22) {
                if !presentation.cast.isEmpty {
                    creditShelf(title: "Cast", credits: presentation.cast)
                }

                if !presentation.crew.isEmpty {
                    creditShelf(title: "Crew", credits: presentation.crew)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        }
    }

    private func creditShelf(
        title: String,
        credits: [PlexCastAndCrewCredit]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(credits) { credit in
                        if let route = credit.route {
                            NavigationLink(value: PlexNavigationRoute.person(route)) {
                                creditCard(credit)
                            }
                            .buttonStyle(.plain)
                        } else {
                            creditCard(credit)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func creditCard(_ credit: PlexCastAndCrewCredit) -> some View {
        let request = imageRequest(for: credit)
        return VStack(alignment: .leading, spacing: 5) {
            PlexArtworkView(
                primaryImageURL: request?.url,
                fallbackImageURL: nil,
                token: request?.token ?? "",
                clientContext: PlexClientContext(clientIdentifier: settingsStore.clientIdentifier),
                placeholderSymbol: "person.crop.square",
                width: portraitSize,
                height: portraitSize,
                cornerRadius: 12
            )

            Text(credit.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            Text(credit.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(width: portraitSize, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(credit.name)
        .accessibilityValue(credit.subtitle)
        .accessibilityAddTraits(credit.route == nil ? [] : .isButton)
    }

    private func imageRequest(for credit: PlexCastAndCrewCredit) -> PlexImageRequest? {
        PlexImageRequest(
            path: credit.thumb,
            serverURL: connectionStore.resolvedServerURL,
            serverToken: settingsStore.trimmedServerToken
        )
    }
}
