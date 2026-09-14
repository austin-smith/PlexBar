import SwiftUI
import QuickLook

/// Opens the source file in Quick Look, independently of the downsampled inline image.
struct StudioImagePreview: View {
    let url: URL?
    var revision = 0
    var previewItems: [URL]?
    @State private var previewURL: URL?
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button {
            previewURL = url
        } label: {
            StudioImageView(url: url, revision: revision)
                .overlay(alignment: .bottomTrailing) {
                    if url != nil {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(8)
                            .background(.regularMaterial, in: .circle)
                            .padding(8)
                            .opacity(isHovered || isFocused ? 1 : 0)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .accessibilityLabel("View larger image")
        .help("View larger image")
        .quickLookPreview($previewURL, in: previewItems ?? [url].compactMap { $0 })
    }
}
