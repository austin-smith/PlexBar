import SwiftUI

struct PosterStackView: View {
    let state: PlexServerPreviewState
    let serverURL: URL?
    let token: String
    let clientContext: PlexClientContext
    var posterWidth: CGFloat = 42
    var posterHeight: CGFloat = 62
    var overlap: CGFloat = 18
    var cornerRadius: CGFloat = 9
    var placeholderSymbol = "photo.stack"

    var body: some View {
        ZStack(alignment: .trailing) {
            if visibleItems.isEmpty {
                placeholderStack
            } else {
                ForEach(Array(visibleItems.reversed().enumerated()), id: \.element.id) { layerIndex, item in
                    poster(for: item)
                        .offset(stackOffset(for: layerIndex, count: visibleItems.count))
                        .zIndex(Double(layerIndex))
                }
            }
        }
        .frame(
            width: posterWidth + overlap * CGFloat(max(stackCount - 1, 0)),
            height: posterHeight + 4
        )
        .offset(y: stackVerticalOffset)
        .accessibilityHidden(true)
    }

    private var visibleItems: [PlexServerPreviewItem] {
        Array(state.items.prefix(4))
    }

    private var stackCount: Int {
        visibleItems.isEmpty ? 4 : visibleItems.count
    }

    private var stackVerticalOffset: CGFloat {
        -CGFloat(max(stackCount - 1, 0))
    }

    @ViewBuilder
    private func poster(for item: PlexServerPreviewItem) -> some View {
        PlexArtworkView(
            primaryImageURL: artworkURL(for: item.displayArtworkPath),
            fallbackImageURL: transcodedArtworkURL(for: item.displayArtworkPath),
            token: token,
            clientContext: clientContext,
            placeholderSymbol: placeholderSymbol,
            width: posterWidth,
            height: posterHeight,
            cornerRadius: cornerRadius
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.26), radius: 8, x: 0, y: 5)
    }

    private var placeholderStack: some View {
        ZStack(alignment: .trailing) {
            ForEach(0..<stackCount, id: \.self) { layerIndex in
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(placeholderFill(for: layerIndex))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                .white.opacity(layerIndex == stackCount - 1 ? 0.12 : 0.08),
                                lineWidth: 0.8
                            )
                    }
                    .frame(width: posterWidth, height: posterHeight)
                    .overlay {
                        if layerIndex == stackCount - 1 && state.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white.opacity(0.9))
                        } else if layerIndex == stackCount - 1 && state.hasLoaded {
                            Image(systemName: placeholderSymbol)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .offset(stackOffset(for: layerIndex, count: stackCount))
                    .zIndex(Double(layerIndex))
            }
        }
    }

    private func placeholderFill(for layerIndex: Int) -> some ShapeStyle {
        let isFrontCard = layerIndex == stackCount - 1

        return LinearGradient(
            colors: [
                isFrontCard
                    ? Color(red: 0.30, green: 0.30, blue: 0.34)
                    : Color(red: 0.23, green: 0.23, blue: 0.27),
                isFrontCard
                    ? Color(red: 0.20, green: 0.20, blue: 0.24)
                    : Color(red: 0.16, green: 0.16, blue: 0.19),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func stackOffset(for layerIndex: Int, count: Int) -> CGSize {
        CGSize(
            width: CGFloat(count - 1 - layerIndex) * -overlap,
            height: CGFloat(layerIndex) * 2
        )
    }

    private func artworkURL(for path: String?) -> URL? {
        guard let serverURL else {
            return nil
        }

        return PlexURLBuilder.mediaURL(serverURL: serverURL, path: path)
    }

    private func transcodedArtworkURL(for path: String?) -> URL? {
        guard let serverURL else {
            return nil
        }

        return PlexURLBuilder.transcodedArtworkURL(
            serverURL: serverURL,
            path: path,
            width: Int(posterWidth * 2),
            height: Int(posterHeight * 2)
        )
    }
}
