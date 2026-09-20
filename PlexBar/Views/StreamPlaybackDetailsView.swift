import SwiftUI

struct StreamPlaybackDetailsView: View {
    let details: PlexSessionPlaybackDetails

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 10) {
            ForEach(details.rows) { row in
                GridRow(alignment: .top) {
                    Text(row.title)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.source)
                        if let output = row.output {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: "arrow.turn.down.right")
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                                Text(output)
                                    .monospacedDigit()
                            }
                            .accessibilityLabel("Output: \(output)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            if let bandwidth = details.bandwidth {
                GridRow(alignment: .top) {
                    Text("Bandwidth").foregroundStyle(.secondary)
                    Text(bandwidth).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .font(.caption)
    }
}

struct StreamDeviceSummaryView: View {
    let playerName: String
    let details: PlexSessionPlaybackDetails

    private var method: String {
        details.method + (details.usesHardware ? " · HW" : "")
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if let bandwidth = details.bandwidth {
                Text("\(playerName) · \(method) · \(bandwidth)")
                    .fixedSize()
            }
            HStack(spacing: 0) {
                Text(playerName)
                    .lineLimit(1)
                Text(" · \(method)")
                    .fixedSize()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
