import PlexModels
import SwiftUI

public struct PlexSeasonPicker: View {
    public let seasons: [PlexMediaItem]
    @Binding public var selection: String?

    public var body: some View {
        Menu {
            Picker("Season", selection: $selection) {
                ForEach(seasons) { season in
                    Text(season.title).tag(Optional(season.id))
                }
            }
            .pickerStyle(.inline)
        } label: {
            #if os(tvOS)
            HStack(spacing: 12) {
                Text(selectedTitle)
                    .font(TVTypography.sectionTitle)
                Image(systemName: "chevron.down")
                    .font(TVTypography.metadata)
            }
            #else
            Text(selectedTitle)
                .font(.title2.weight(.semibold))
            #endif
        }
        #if os(tvOS)
        .buttonStyle(.borderless)
        #else
        .menuStyle(.borderlessButton)
        #endif
        .fixedSize()
        .accessibilityLabel("Season")
        .accessibilityValue(selectedTitle)
        .accessibilityIdentifier("season-picker")
    }

    private var selectedTitle: String {
        seasons.first { $0.id == selection }?.title ?? "Season"
    }

    public init(seasons: [PlexMediaItem], selection: Binding<String?>) {
        self.seasons = seasons
        self._selection = selection
    }
}
