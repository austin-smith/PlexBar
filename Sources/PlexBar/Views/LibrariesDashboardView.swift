import SwiftUI

struct LibrariesDashboardView: View {
    let settingsStore: PlexSettingsStore
    let libraryStore: PlexLibraryStore

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(libraryStore.libraries) { library in
                LibraryCardView(
                    library: library,
                    serverURL: settingsStore.normalizedServerURL,
                    token: settingsStore.trimmedServerToken,
                    clientContext: PlexClientContext(clientIdentifier: settingsStore.clientIdentifier)
                )
            }
        }
    }
}

private struct LibraryCardView: View {
    let library: PlexLibrary
    let serverURL: URL?
    let token: String
    let clientContext: PlexClientContext

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { proxy in
                PlexArtworkView(
                    primaryImageURL: compositeURL,
                    fallbackImageURL: fallbackArtworkURL,
                    token: token,
                    clientContext: clientContext,
                    placeholderSymbol: library.type.symbolName,
                    width: proxy.size.width,
                    height: proxy.size.height,
                    cornerRadius: 16
                )
            }

            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(0.2),
                    .black.opacity(0.78),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: library.type.symbolName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.68))

                    Text(library.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    Text(library.itemSummary)
                        .lineLimit(1)
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))

                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 152)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var compositeURL: URL? {
        guard let serverURL else {
            return nil
        }

        return PlexURLBuilder.mediaURL(serverURL: serverURL, path: library.compositePath)
    }

    private var fallbackArtworkURL: URL? {
        guard let serverURL else {
            return nil
        }

        return PlexURLBuilder.mediaURL(
            serverURL: serverURL,
            path: library.artPath ?? library.thumbPath
        )
    }

    private var statusLine: String {
        guard let statusDate = library.statusDate else {
            return library.type.displayName
        }

        return "\(library.statusPrefix) \(statusDate.formatted(.relative(presentation: .named)))"
    }
}
