import PlexModels
import SwiftUI

public struct PlexMediaMetadataView: View {
    public let presentation: PlexMediaMetadataPresentation

    public init(item: PlexMediaItem) {
        presentation = PlexMediaMetadataPresentation(item: item)
    }

    public var body: some View {
        if !presentation.facts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Details")
                    #if os(tvOS)
                    .font(TVTypography.sectionTitle)
                    #else
                    .font(.headline)
                    #endif
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(presentation.facts) { fact in
                        PlexMediaMetadataFactRow(fact: fact)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            #if os(tvOS)
            .focusable()
            #endif
        }
    }
}

private struct PlexMediaMetadataFactRow: View {
    let fact: PlexMediaMetadataFact
    @ScaledMetric(relativeTo: .callout) private var labelWidth = 112.0

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(fact.label)
                .font(valueFont)
                .foregroundStyle(.secondary)
                .frame(width: resolvedLabelWidth, alignment: .trailing)
                .accessibilityHidden(true)

            Text(fact.value)
                .font(valueFont)
                #if !os(tvOS)
                .textSelection(.enabled)
                #endif
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
        }
        .accessibilityRepresentation {
            Text("\(fact.label): \(fact.value)")
        }
    }

    private var valueFont: Font {
        #if os(tvOS)
        TVTypography.metadata
        #else
        .callout
        #endif
    }

    private var resolvedLabelWidth: CGFloat {
        #if os(tvOS)
        160
        #else
        labelWidth
        #endif
    }
}
