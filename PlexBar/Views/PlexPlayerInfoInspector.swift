import SwiftUI

struct PlexPlayerPlaybackInfoPresentation: Equatable, Sendable {
    let title: String
    let hierarchyLine: String?

    init(item: PlexMediaItem) {
        title = item.title
        hierarchyLine = Self.hierarchyLine(for: item)
    }

    private static func hierarchyLine(for item: PlexMediaItem) -> String? {
        let values: [String?] = switch item.type?.lowercased() {
        case "episode", "track": [item.grandparentTitle, item.parentTitle]
        default: [item.parentTitle, item.grandparentTitle]
        }

        var seen: Set<String> = []
        let hierarchy = values
            .compactMap { $0?.nilIfBlank }
            .filter { seen.insert($0).inserted }
        return hierarchy.isEmpty ? nil : hierarchy.joined(separator: " · ")
    }
}

struct PlexPlayerPlaybackInfoHUD: View {
    let session: PlexPlayerSessionModel

    private var presentation: PlexPlayerPlaybackInfoPresentation {
        PlexPlayerPlaybackInfoPresentation(item: session.presentation.item)
    }

    private var videoFacts: [PlexNativeMediaDiagnosticFact] {
        session.deliveredMediaDiagnosticFacts.filter {
            switch $0.kind {
            case .resolution, .frameRate, .videoCodec, .dynamicRange, .videoBitRate:
                true
            case .audioCodec, .channels, .sampleRate, .audioBitRate:
                false
            }
        }
    }

    private var audioFacts: [PlexNativeMediaDiagnosticFact] {
        session.deliveredMediaDiagnosticFacts.filter {
            switch $0.kind {
            case .audioCodec, .channels, .sampleRate, .audioBitRate:
                true
            case .resolution, .frameRate, .videoCodec, .dynamicRange, .videoBitRate:
                false
            }
        }
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
                        rows: playbackRows
                    )

                    if !videoFacts.isEmpty {
                        PlexPlaybackInfoSection(
                            title: "Video",
                            systemImage: "film",
                            rows: videoFacts.map { ($0.label, $0.value) }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                Divider()

                VStack(alignment: .leading, spacing: 22) {
                    if !audioFacts.isEmpty {
                        PlexPlaybackInfoSection(
                            title: "Audio",
                            systemImage: "waveform",
                            rows: audioFacts.map { ($0.label, $0.value) }
                        )
                    }

                    if !session.playbackMetricDiagnosticFacts.isEmpty {
                        PlexPlaybackInfoSection(
                            title: "Performance",
                            systemImage: "gauge.with.dots.needle.50percent",
                            rows: session.playbackMetricDiagnosticFacts.map { ($0.label, $0.value) }
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
                Text(presentation.title)
                    .font(.headline)
                    .lineLimit(2)
                    .textSelection(.enabled)

                if let hierarchyLine = presentation.hierarchyLine {
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

    private var playbackRows: [(String, String)] {
        var rows = [("Delivery", session.playbackMethodLabel)]
        if let waitingReason = session.playbackWaitingReasonLabel {
            rows.append(("Waiting", waitingReason))
        }
        return rows
    }
}

private struct PlexPlaybackInfoSection: View {
    let title: String
    let systemImage: String
    let rows: [(label: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
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
