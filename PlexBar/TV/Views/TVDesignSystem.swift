import PlexModels
import SwiftUI

enum TVTheme {
    static let plexGold = Color(red: 0.90, green: 0.63, blue: 0.05)
    static let canvas = Color(red: 0.025, green: 0.028, blue: 0.035)
}

enum TVTypography {
    static let title = Font.system(size: 36, weight: .semibold)
    static let sectionTitle = Font.system(size: 28, weight: .semibold)
    static let body = Font.system(size: 24)
    static let action = Font.system(size: 24, weight: .semibold)
    static let cardTitle = Font.system(size: 20, weight: .semibold)
    static let metadata = Font.system(size: 20)
    static let caption = Font.system(size: 18)
}

enum TVLayout {
    static let sectionSpacing: CGFloat = 32
    static let cardSpacing: CGFloat = 24
    static let posterColumns = 7
    static let episodeColumns = 6
    static let castColumns = 11
    static let posterGridColumns = Array(
        repeating: GridItem(.flexible(), spacing: cardSpacing, alignment: .top),
        count: posterColumns
    )
}

extension PlexMediaArtworkShape {
    var shelfColumnCount: Int {
        switch self {
        case .poster: TVLayout.posterColumns
        case .landscape: TVLayout.episodeColumns
        case .square: TVLayout.posterColumns
        }
    }
}

enum TVLockupSizing: Sendable {
    case shelf
    case grid
}

struct TVCanvasBackground: View {
    var body: some View {
        TVTheme.canvas
            .ignoresSafeArea()
    }
}

struct TVBrandMark: View {
    var size: CGFloat = 88

    var body: some View {
        Image("ribbon-balloon")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("PlexBar")
    }
}

/// Resolve one request before laying out its image. The request identity includes
/// the server and dimensions, so reused rows never retain another request's art.
struct TVArtworkImage<Content: View>: View {
    @Environment(TVAppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let path: String?
    let width: Int
    let height: Int
    var usesOriginalImage = false
    @ViewBuilder let content: (Image?) -> Content
    @State private var url: URL?

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(
            animation: PlexMotion.contentReplacementAnimation(reduceMotion: reduceMotion)
        )) { phase in
            content(phase.image)
        }
        .task(id: requestID) {
            url = nil
            let resolvedURL = await store.artworkURL(
                path: path, width: width, height: height, usesOriginalImage: usesOriginalImage
            )
            guard !Task.isCancelled else { return }
            url = resolvedURL
        }
    }

    private var requestID: String {
        [path ?? "", String(width), String(height), String(usesOriginalImage),
         store.connection?.serverURL.absoluteString ?? "",
         store.connection?.token ?? ""].joined(separator: "|")
    }
}

struct TVPlexArtwork: View {
    let path: String?
    let width: Int
    let height: Int
    let systemImage: String
    var usesOriginalImage = false
    var contentMode: ContentMode = .fill
    var showsPlaceholder = true

    var body: some View {
        // A flexible base owns the size, including while loading or missing art.
        // The decoded image can never expand a shelf or change its aspect ratio.
        Rectangle()
            .fill(showsPlaceholder ? Color.white.opacity(0.06) : .clear)
            .overlay {
                TVArtworkImage(path: path, width: width, height: height, usesOriginalImage: usesOriginalImage) { image in
                    GeometryReader { geometry in
                        if let image {
                            image.resizable()
                                .aspectRatio(contentMode: contentMode)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        } else if showsPlaceholder {
                            Image(systemName: systemImage)
                                .font(.largeTitle.weight(.ultraLight))
                                .foregroundStyle(.tertiary)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        }
                    }
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

struct TVProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(.white.opacity(0.28))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.white)
                        .frame(width: geometry.size.width * min(max(progress, 0), 1))
                }
        }
        .frame(height: 4)
        .accessibilityLabel("Playback progress")
        .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
    }
}

struct TVPlaybackButton: View {
    @Environment(TVAppStore.self) private var store

    let item: PlexMediaItem
    let title: String?
    let systemImage: String
    let preparationKind: TVPlaybackPreparationKind
    let fillsAvailableWidth: Bool
    let isIconOnly: Bool
    let action: () -> Void

    init(
        item: PlexMediaItem,
        title: String? = nil,
        systemImage: String = "play.fill",
        preparationKind: TVPlaybackPreparationKind = .content,
        fillsAvailableWidth: Bool = true,
        isIconOnly: Bool = false,
        action: @escaping () -> Void
    ) {
        self.item = item
        self.title = title
        self.systemImage = systemImage
        self.preparationKind = preparationKind
        self.fillsAvailableWidth = fillsAvailableWidth
        self.isIconOnly = isIconOnly
        self.action = action
    }

    @ViewBuilder
    var body: some View {
        Button(action: action) {
            buttonLabel
                .frame(maxWidth: fillsAvailableWidth ? .infinity : nil)
        }
        .buttonStyle(.bordered)
        .disabled(isPreparing)
        .accessibilityLabel(isPreparing ? preparingAccessibilityLabel : playbackAccessibilityLabel)
    }

    private var buttonLabel: some View {
        Group {
            if isIconOnly {
                Image(systemName: isPreparing ? "progress.indicator" : systemImage)
            } else {
                Label(isPreparing ? "Preparing…" : actionTitle,
                      systemImage: isPreparing ? "progress.indicator" : systemImage)
            }
        }
        .font(TVTypography.action)
    }

    private var isPreparing: Bool {
        store.isPreparingPlayback(item, kind: preparationKind)
    }

    private var actionTitle: String {
        title ?? (item.resumeSeconds > 0 ? "Resume" : "Play")
    }

    private var preparingAccessibilityLabel: String {
        if let title {
            return "Preparing \(title) for \(item.title)"
        }
        return "Preparing \(item.title)"
    }

    private var playbackAccessibilityLabel: String {
        if let title {
            return "\(title) for \(item.title)"
        }
        return item.resumeSeconds > 0
            ? "Resume \(item.title)"
            : "Play \(item.title)"
    }
}

struct TVMediaLockup: View {
    @Environment(TVAppStore.self) private var store

    let item: PlexMediaItem
    let artworkStyle: PlexMediaArtworkShape
    let artworkLayout: PlexMediaArtworkLayout
    let sizing: TVLockupSizing
    let columnCount: Int?
    let showsEpisodeNumber: Bool
    let selectionAction: (() -> Void)?
    let isSelected: Bool
    @FocusState private var isFocused: Bool

    init(
        item: PlexMediaItem,
        artworkStyle: PlexMediaArtworkShape,
        artworkLayout: PlexMediaArtworkLayout = .automatic,
        sizing: TVLockupSizing = .shelf,
        columnCount: Int? = nil,
        showsEpisodeNumber: Bool = false,
        selectionAction: (() -> Void)? = nil,
        isSelected: Bool = false
    ) {
        self.item = item
        self.artworkStyle = artworkStyle
        self.artworkLayout = artworkLayout
        self.sizing = sizing
        self.columnCount = columnCount
        self.showsEpisodeNumber = showsEpisodeNumber
        self.selectionAction = selectionAction
        self.isSelected = isSelected
    }

    var body: some View {
        Group {
            if let selectionAction {
                Button(action: selectionAction) { card }
            } else if item.type?.lowercased() == "clip" {
                Button { store.play(item) } label: { card }
            } else {
                NavigationLink(value: TVNavigationRoute.media(item)) { card }
            }
        }
        .buttonStyle(.borderless)
        .modifier(TVLockupFrame(style: artworkStyle, sizing: sizing, columnCount: columnCount))
        .focused($isFocused)
        .accessibilityIdentifier("media.\(item.type ?? "unknown").\(item.ratingKey)")
        .onPlayPauseCommand {
            if isFocused, item.tvCanStartPlayback { store.play(item) }
        }
        .accessibilityLabel([title, subtitle].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(item.type?.lowercased() == "clip"
            ? "Select to play."
            : item.tvCanStartPlayback ? "Press Play/Pause to play. Select for details." : "Select for details.")
        .contextMenu {
            if item.tvCanStartPlayback {
                Button(item.resumeSeconds > 0 ? "Resume" : "Play", systemImage: "play.fill") {
                    store.play(item)
                }
                if item.isPlayable, item.resumeSeconds > 0 {
                    Button("Play from Beginning", systemImage: "backward.end.fill") {
                        store.play(item, resume: false)
                    }
                }
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            artwork
            TVMediaCardLabels(
                title: title,
                subtitle: subtitle,
                titleLineLimit: showsEpisodeNumber ? 1 : 2
            )
        }
    }

    private var title: String {
        guard showsEpisodeNumber, let index = item.index else { return item.displayTitle }
        return "\(index). \(item.displayTitle)"
    }

    private var subtitle: String? {
        guard showsEpisodeNumber else { return item.subtitle }
        return item.formattedDuration
    }

    @ViewBuilder
    private var artwork: some View {
        let image = TVPlexArtwork(
            path: artworkPath,
            width: artworkStyle == .landscape ? 960 : 600,
            height: artworkStyle == .landscape ? 540 : (artworkStyle == .square ? 600 : 900),
            systemImage: item.type?.lowercased() == "track" ? "music.note" : "film"
        )
        .aspectRatio(artworkStyle.aspectRatio, contentMode: .fit)
        .overlay(alignment: .bottom) {
            if let progress = item.progress, progress > 0, progress < 0.98 {
                TVProgressBar(progress: progress)
                    .padding(10)
            }
        }
        .clipShape(.rect(cornerRadius: 12))
        .plexWatchedIndicator(isWatched: item.isWatched, scale: .large)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? TVTheme.plexGold : .clear, lineWidth: 3)
        }
        .hoverEffect(.highlight)

        image
    }

    private var artworkPath: String? {
        PlexMediaArtworkPresentation(item: item, layout: artworkLayout).path
    }
}

private struct TVLockupFrame: ViewModifier {
    let style: PlexMediaArtworkShape
    let sizing: TVLockupSizing
    let columnCount: Int?

    @ViewBuilder
    func body(content: Content) -> some View {
        switch sizing {
        case .shelf:
            content.containerRelativeFrame(.horizontal, count: columnCount ?? style.shelfColumnCount, spacing: TVLayout.cardSpacing)
        case .grid:
            content.frame(maxWidth: .infinity)
        }
    }
}

struct TVPersonLockup: View {
    let credit: PlexCastAndCrewCredit

    @ViewBuilder
    var body: some View {
        if let route = credit.route {
            NavigationLink(value: TVNavigationRoute.person(route)) {
                label
            }
            .buttonStyle(.borderless)
            .containerRelativeFrame(.horizontal, count: TVLayout.castColumns, spacing: TVLayout.cardSpacing)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Opens this person's Plex appearances.")
        } else {
            label
                .containerRelativeFrame(.horizontal, count: TVLayout.castColumns, spacing: TVLayout.cardSpacing)
                .accessibilityElement(children: .combine)
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 12) {
            portrait
            TVMediaCardLabels(title: credit.name, subtitle: credit.subtitle)
        }
    }

    private var portrait: some View {
        TVPlexArtwork(
            path: credit.thumb,
            width: 320,
            height: 320,
            systemImage: "person.fill"
        )
        .aspectRatio(1, contentMode: .fit)
        .containerRelativeFrame(.horizontal, count: TVLayout.castColumns, spacing: TVLayout.cardSpacing)
        .clipShape(.rect(cornerRadius: 12))
        .hoverEffect(.highlight)
    }

    private var accessibilityLabel: String {
        "\(credit.name), \(credit.subtitle)"
    }
}

struct TVMediaCardLabels: View {
    let title: String
    let subtitle: String?
    var titleLineLimit = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(TVTypography.cardTitle)
                .lineLimit(titleLineLimit, reservesSpace: titleLineLimit > 1)

            if let subtitle {
                Text(subtitle)
                    .font(TVTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TVMediaGrid: View {
    let items: [PlexMediaItem]
    var artworkLayout: PlexMediaArtworkLayout = .automatic
    var onItemAppear: ((PlexMediaItem) async -> Void)?

    var body: some View {
        LazyVGrid(columns: TVLayout.posterGridColumns, alignment: .leading, spacing: 28) {
            ForEach(items) { item in
                TVMediaLockup(
                    item: item,
                    artworkStyle: PlexMediaArtworkPresentation(item: item, layout: artworkLayout).shape,
                    artworkLayout: artworkLayout,
                    sizing: .grid
                )
                .task { await onItemAppear?(item) }
            }
        }
    }
}

struct TVLoadingView: View {
    let title: String

    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .controlSize(.large)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
