import SwiftUI

struct PlexActivitySummaryView: View {
    let summary: PlexActivitySummary
    let isStale: Bool
    @State private var showsBandwidthDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    streamCount
                    Spacer(minLength: 0)
                    bandwidth
                }
                VStack(alignment: .leading, spacing: 6) {
                    streamCount
                    bandwidth
                }
            }

            if !methodSummary.isEmpty {
                Text(methodSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isStale {
                Text("Last known activity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var streamCount: some View {
        Text(summary.streamCount == 1 ? "1 active stream" : "\(summary.streamCount.formatted()) active streams")
            .font(.headline)
            .fixedSize()
    }

    @ViewBuilder
    private var bandwidth: some View {
        if summary.streamCount > 0 {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(bandwidthSummary)
                    .font(.body)
                Button("Bandwidth details", systemImage: "info.circle") {
                    showsBandwidthDetails.toggle()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("View bandwidth and local/remote totals")
                .popover(isPresented: $showsBandwidthDetails) {
                    bandwidthDetails
                }
            }
            .fixedSize()
        }
    }

    private var methodSummary: String {
        var pieces: [String] = []
        if summary.directPlayCount > 0 { pieces.append("\(summary.directPlayCount.formatted()) direct play") }
        if summary.directStreamCount > 0 { pieces.append("\(summary.directStreamCount.formatted()) direct stream") }
        if summary.transcodingCount > 0 { pieces.append("\(summary.transcodingCount.formatted()) transcoding") }
        if summary.unknownCount > 0 { pieces.append("\(summary.unknownCount.formatted()) unknown") }
        return pieces.joined(separator: " · ")
    }

    private var bandwidthSummary: String {
        guard summary.reportedBandwidthCount > 0 else { return "Unavailable" }
        return PlexActivitySummary.bandwidthText(kbps: summary.totalBandwidthKbps)
    }

    private var bandwidthDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stream bandwidth")
                .font(.headline)
            if summary.reportedBandwidthCount > 0 {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    bandwidthRow(summary.hasPartialBandwidth ? "Known subtotal" : "Total", value: summary.totalBandwidthKbps)
                    bandwidthRow("Local", value: summary.localBandwidthKbps)
                    bandwidthRow("Remote", value: summary.remoteBandwidthKbps)
                    if summary.unknownLocationCount > 0 {
                        bandwidthRow("Unknown location", value: summary.unknownLocationBandwidthKbps)
                    }
                }
            }
        }
        .fixedSize()
        .padding(16)
    }

    private func bandwidthRow(_ title: String, value: Double) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(PlexActivitySummary.bandwidthText(kbps: value))
                .monospacedDigit()
                .gridColumnAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
