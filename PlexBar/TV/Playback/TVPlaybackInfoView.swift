import SwiftUI

struct TVPlaybackInfoView: View {
    let presentation: PlexPlaybackInfoPresentation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header
                Divider()
                sections
            }
            .safeAreaPadding()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Playback Info")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(presentation.item.title)
                .font(TVTypography.sectionTitle)
                .lineLimit(2)

            if let hierarchyLine = presentation.item.hierarchyLine {
                Text(hierarchyLine)
                    .font(TVTypography.sectionTitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var sections: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 48, alignment: .top),
                count: 3
            ),
            alignment: .leading,
            spacing: 32
        ) {
            TVPlaybackInfoSection(
                title: "Playback",
                systemImage: "play.circle.fill",
                rows: presentation.playbackRows
            )

            if !presentation.videoRows.isEmpty {
                TVPlaybackInfoSection(
                    title: "Delivered Video",
                    systemImage: "film.fill",
                    rows: presentation.videoRows
                )
            }

            if !presentation.audioRows.isEmpty {
                TVPlaybackInfoSection(
                    title: "Delivered Audio",
                    systemImage: "waveform",
                    rows: presentation.audioRows
                )
            }

            if !presentation.performanceRows.isEmpty {
                TVPlaybackInfoSection(
                    title: "Performance",
                    systemImage: "gauge.with.dots.needle.50percent",
                    rows: presentation.performanceRows
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct TVPlaybackInfoSection: View {
    let title: String
    let systemImage: String
    let rows: [PlexPlaybackInfoPresentation.Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: systemImage)
                .font(TVTypography.sectionTitle)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 24) {
                        Text(row.label)
                            .foregroundStyle(.secondary)
                        Text(row.value)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.label)
                    .accessibilityValue(row.value)
                }
            }
            .font(TVTypography.body)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
