import PlexClientKit
import SwiftUI

struct PlexMediaFactsView: View {
    let presentation: PlexMediaFactsPresentation
    var genres: String? = nil
    var badgeFont: Font = .subheadline
    @ScaledMetric(relativeTo: .headline) private var separatorPadding = 6.0

    private enum Segment {
        case text(String)
        case contentRating(String)
    }

    private var segments: [Segment] {
        var segments = presentation.facts.map(Segment.text)
        if let contentRating = presentation.contentRating {
            segments.append(.contentRating(contentRating))
        }
        if let genres {
            segments.append(.text(genres))
        }
        return segments
    }

    var body: some View {
        let segments = segments

        if !segments.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        if index > 0 {
                            separator
                        }
                        segmentView(segment)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        segmentView(segment)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func segmentView(_ segment: Segment) -> some View {
        switch segment {
        case .text(let text):
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        case .contentRating(let rating):
            PlexContentRatingBadge(rating: rating, font: badgeFont)
        }
    }

    private var separator: some View {
        Text("·")
            .fixedSize()
            .padding(.horizontal, separatorPadding)
            .accessibilityHidden(true)
    }
}

struct PlexContentRatingBadge: View {
    let rating: String
    var font: Font = .subheadline
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .body) private var horizontalPadding = 4.0
    @ScaledMetric(relativeTo: .body) private var verticalPadding = 1.0

    var body: some View {
        Text(rating)
            .font(font.weight(.medium))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(.foreground.opacity(contrast == .increased ? 1 : 0.55), lineWidth: 0.75)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel(Text("Content rating: \(rating)"))
    }
}

#Preview("Content ratings") {
    VStack(alignment: .leading, spacing: 16) {
        ForEach(["TV-Y7-FV", "TV-MA", "PG-13", "NC-17", "12A", "FSK 16", "NR"], id: \.self) { rating in
            PlexMediaFactsView(presentation: .init(
                facts: ["36 min", "April 1, 2025"],
                contentRating: rating
            ))
        }
    }
    .font(.headline)
    .padding()
    .frame(width: 320)
}

#Preview("Narrow metadata") {
    PlexMediaFactsView(presentation: .init(
        facts: ["36 min", "September 12, 2026"],
        contentRating: "TV-MA (L, S, V)"
    ))
    .font(.headline)
    .padding()
    .frame(width: 180)
}
