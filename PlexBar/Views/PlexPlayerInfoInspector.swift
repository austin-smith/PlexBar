import SwiftUI

struct PlexPlayerPlaybackInfoHUD: View {
    let session: PlexPlayerSessionModel

    private var presentation: PlexPlaybackInfoPresentation {
        PlexPlaybackInfoPresentation(
            item: session.presentation.item,
            deliveryLabel: session.playbackMethodLabel,
            videoQualityLabel: session.presentation.plan.mediaKind == .video
                ? session.presentation.videoQuality.label
                : nil,
            waitingReasonLabel: session.playbackWaitingReasonLabel,
            deliveredMediaFacts: session.engine.mediaFacts,
            playbackMetricFacts: session.playbackMetricDiagnosticFacts
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            Divider()

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 22) {
                    PlexPlaybackInfoSection(
                        title: "Playback",
                        systemImage: "play.circle",
                        rows: presentation.playbackRows
                    )

                    if !presentation.videoRows.isEmpty {
                        PlexPlaybackInfoSection(
                            title: "Video",
                            systemImage: "film",
                            rows: presentation.videoRows
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                Divider()

                VStack(alignment: .leading, spacing: 22) {
                    if !presentation.audioRows.isEmpty {
                        PlexPlaybackInfoSection(
                            title: "Audio",
                            systemImage: "waveform",
                            rows: presentation.audioRows
                        )
                    }

                    if !presentation.performanceRows.isEmpty {
                        PlexPlaybackInfoSection(
                            title: "Performance",
                            systemImage: "gauge.with.dots.needle.50percent",
                            rows: presentation.performanceRows
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(20)
        .frame(width: 560)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Playback Info")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.item.title)
                    .font(.headline)
                    .lineLimit(2)
                    .textSelection(.enabled)

                if let hierarchyLine = presentation.item.hierarchyLine {
                    Text(hierarchyLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 20)

            VStack(alignment: .trailing, spacing: 3) {
                Text(session.playbackStatusLabel)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

}

private struct PlexPlaybackInfoSection: View {
    let title: String
    let systemImage: String
    let rows: [PlexPlaybackInfoPresentation.Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.label)
                            .foregroundStyle(.secondary)
                            .frame(width: 106, alignment: .leading)
                            .accessibilityHidden(true)

                        Text(row.value)
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.label)
                    .accessibilityValue(row.value)
                }
            }
            .font(.callout)
        }
    }
}
