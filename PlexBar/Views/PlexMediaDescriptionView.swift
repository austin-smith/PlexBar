import SwiftUI

struct PlexMediaDescriptionView: View {
    let title: String
    let summary: String
    @State private var availableWidth: CGFloat = 0
    @State private var presentsDescription = false
    @ScaledMetric(relativeTo: .body) private var fontScale = 1.0

    private var textFont: NSFont {
        let font = NSFont.preferredFont(forTextStyle: .body)
        return font.withSize(font.pointSize * fontScale)
    }

    var body: some View {
        let lineBreak = PlexDescriptionLineBreak(summary: summary, width: availableWidth, font: textFont)

        Group {
            if let lineBreak {
                VStack(alignment: .leading, spacing: 3) {
                    Text(lineBreak.firstLine)
                        .lineLimit(1, reservesSpace: true)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(lineBreak.remainingText)
                            .lineLimit(1, reservesSpace: true)
                            .truncationMode(.tail)

                        Button("MORE") { presentsDescription = true }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
            } else {
                Text(summary)
                    .lineSpacing(3)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(Font(textFont))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
            availableWidth = $0
        }
        .sheet(isPresented: $presentsDescription) {
            PlexFullDescriptionSheet(title: title, summary: summary)
        }
        .onChange(of: summary) {
            presentsDescription = false
        }
    }
}

private struct PlexFullDescriptionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ScrollView {
                Text(summary)
                    .font(.body)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: 360)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .foregroundStyle(.primary)
        .padding(24)
        .frame(width: 560)
    }
}
