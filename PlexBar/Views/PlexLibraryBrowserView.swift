import PlexModels
import SwiftUI

struct PlexLibraryBrowserView: View {
    let library: PlexLibrary
    @Bindable var searchStore: PlexLibrarySearchStore
    @Binding var scrollPosition: ScrollPosition
    @Bindable var browserStore: PlexBrowserStore
    @Bindable var settingsStore: PlexSettingsStore
    @Bindable var connectionStore: PlexConnectionStore
    @Bindable var playerCoordinator: PlexPlayerCoordinator
    @State private var presentedValueFilter: PlexLibraryFilterDefinition?
    private let artworkPrefetcher = PlexArtworkPrefetcher.shared

    var body: some View {
        Group {
            if browserStore.isLoading(
                library,
                searchQuery: searchStore.displayedQuery,
                browseOptions: searchStore.displayedOptions
            ) && items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading \(library.title)")
            } else if let errorMessage = browserStore.errorMessage(
                for: library,
                searchQuery: searchStore.displayedQuery,
                browseOptions: searchStore.displayedOptions
            ), items.isEmpty {
                ContentUnavailableView {
                    Label("Couldn’t Load \(library.title)", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again", action: refresh)
                }
            } else if items.isEmpty {
                if searchStore.displayedQuery.isEmpty {
                    ContentUnavailableView("No Items", systemImage: library.type.symbolName)
                } else {
                    ContentUnavailableView.search(text: searchStore.displayedQuery)
                }
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: PlexMediaPosterCard.standardGridColumns,
                        alignment: .leading,
                        spacing: 24
                    ) {
                        ForEach(items) { item in
                            NavigationLink(value: PlexNavigationRoute.media(PlexMediaRoute(item: item))) {
                                PlexMediaPosterCard(
                                    item: item,
                                    settingsStore: settingsStore,
                                    serverURL: connectionStore.resolvedServerURL
                                )
                            }
                            .plexMediaContextMenu(
                                for: item,
                                library: library,
                                browserStore: browserStore,
                                playerCoordinator: playerCoordinator
                            )
                            .buttonStyle(.plain)
                            .task {
                                await prefetchArtwork(after: item)
                                await browserStore.loadMoreIfNeeded(
                                    in: library,
                                    searchQuery: searchStore.displayedQuery,
                                    browseOptions: searchStore.displayedOptions,
                                    currentItem: item
                                )
                            }
                        }

                        if browserStore.isLoading(
                            library,
                            searchQuery: searchStore.displayedQuery,
                            browseOptions: searchStore.displayedOptions
                        ) {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 80)
                                .accessibilityLabel("Loading more \(library.title)")
                        }
                    }
                    .scrollTargetLayout()
                    .scenePadding()
                }
                .scrollPosition($scrollPosition)
            }
        }
        .overlay(alignment: .top) {
            searchProgressIndicator
        }
        .navigationTitle(library.title)
        .searchable(text: $searchStore.text, placement: .toolbar, prompt: "Search \(library.title)")
        .focusedSceneValue(
            \.plexRefreshCommand,
            PlexFocusedCommandAction(
                title: "Refresh \(library.title)",
                isEnabled: !searchStore.isUpdating
                    && !browserStore.isLoading(
                        library,
                        searchQuery: searchStore.displayedQuery,
                        browseOptions: searchStore.displayedOptions
                    ),
                perform: refresh
            )
        )
        .task {
            await browserStore.loadLibraryProviderCapabilities()
        }
        .task(id: LibraryBrowseTask(
            libraryID: library.id,
            query: searchStore.normalizedQuery,
            options: searchStore.selectedOptions
        )) {
            await searchStore.update { requestedQuery, requestedOptions in
                await browserStore.load(
                    library,
                    searchQuery: requestedQuery,
                    browseOptions: requestedOptions
                )
            }
        }
        .onChange(of: LibraryBrowseTask(
            libraryID: library.id,
            query: searchStore.normalizedQuery,
            options: searchStore.selectedOptions
        )) { oldTask, newTask in
            guard oldTask != newTask else {
                return
            }
            scrollPosition.scrollTo(edge: .top)
        }
        .sheet(item: $presentedValueFilter) { filter in
            PlexLibraryFilterPicker(
                filter: filter,
                browserStore: browserStore,
                searchStore: searchStore
            )
        }
        .toolbar {
            ToolbarItemGroup {
                contentTypeMenu
                sortMenu
                filterMenu
                Button("Refresh \(library.title)", systemImage: "arrow.clockwise", action: refresh)
                    .disabled(
                        searchStore.isUpdating
                            || browserStore.isLoading(
                                library,
                                searchQuery: searchStore.displayedQuery,
                                browseOptions: searchStore.displayedOptions
                            )
                    )
            }
        }
    }

    private var items: [PlexMediaItem] {
        browserStore.items(
            in: library,
            searchQuery: searchStore.displayedQuery,
            browseOptions: searchStore.displayedOptions
        )
    }

    private var browseDefinition: PlexLibraryBrowseDefinition? {
        try? browserStore.browseDefinition(for: library)?
            .selecting(searchStore.selectedOptions.contentTypePath)
    }

    @ViewBuilder
    private var contentTypeMenu: some View {
        if let definition = browserStore.browseDefinition(for: library), definition.types.count > 1 {
            let selectedPath = searchStore.selectedOptions.contentTypePath ?? definition.contentPath
            let title = definition.types.first { $0.key == selectedPath }?.title ?? "Browse"
            Menu(title) {
                ForEach(definition.types) { type in
                    Button {
                        searchStore.selectContentType(
                            path: type.key == definition.contentPath ? nil : type.key
                        )
                    } label: {
                        menuLabel(type.title, isSelected: type.key == selectedPath)
                    }
                }
            }
            .help("Choose the type of items to browse")
        }
    }

    private var selectedSortDefinition: PlexLibrarySortDefinition? {
        guard let selectedSort = searchStore.selectedOptions.sort else {
            return nil
        }
        return browseDefinition?.sorts.first { $0.id == selectedSort.sortID }
    }

    private var sortMenu: some View {
        Menu("Sort", systemImage: "arrow.up.arrow.down") {
            Button(action: selectDefaultSort) {
                menuLabel("Default", isSelected: searchStore.selectedOptions.sort == nil)
            }

            if let browseDefinition, !browseDefinition.sorts.isEmpty {
                Divider()
                ForEach(browseDefinition.sorts) { sort in
                    Button {
                        searchStore.selectSort(sort)
                    } label: {
                        menuLabel(
                            sort.title,
                            isSelected: searchStore.selectedOptions.sort?.sortID == sort.id
                        )
                    }
                }
            }

            if let selectedSortDefinition {
                Divider()
                Section("Direction") {
                    Button {
                        searchStore.selectSortDirection(.ascending, definition: selectedSortDefinition)
                    } label: {
                        menuLabel(
                            PlexLibrarySortDirection.ascending.title,
                            isSelected: searchStore.selectedOptions.sort?.direction == .ascending
                        )
                    }

                    if selectedSortDefinition.descendingKey != nil {
                        Button {
                            searchStore.selectSortDirection(.descending, definition: selectedSortDefinition)
                        } label: {
                            menuLabel(
                                PlexLibrarySortDirection.descending.title,
                                isSelected: searchStore.selectedOptions.sort?.direction == .descending
                            )
                        }
                    }
                }
            }
        }
        .disabled(browseDefinition?.sorts.isEmpty != false)
        .accessibilityLabel("Sort \(library.title)")
    }

    private var filterMenu: some View {
        Menu("Filter", systemImage: "line.3.horizontal.decrease") {
            if let booleanFilters = browseDefinition?.booleanFilters,
               !booleanFilters.isEmpty {
                Section("Status") {
                    ForEach(booleanFilters) { filter in
                        Toggle(
                            filter.title,
                            isOn: Binding(
                                get: { searchStore.isBooleanFilterEnabled(filter) },
                                set: { searchStore.setBooleanFilter(filter, isEnabled: $0) }
                            )
                        )
                    }
                }
            }

            if let valueFilters = browseDefinition?.valueFilters,
               !valueFilters.isEmpty {
                Section("Details") {
                    ForEach(valueFilters) { filter in
                        Button {
                            presentedValueFilter = filter
                        } label: {
                            valueFilterMenuLabel(filter)
                        }
                    }
                }
            }

            Divider()
            Button("Clear Filters", action: searchStore.clearFilters)
                .disabled(!searchStore.hasSelectedFilters)
        }
        .disabled(browseDefinition?.filters.isEmpty != false)
        .accessibilityLabel("Filter \(library.title)")
    }

    @ViewBuilder
    private func valueFilterMenuLabel(_ filter: PlexLibraryFilterDefinition) -> some View {
        let selectionCount = searchStore.selectedValueCount(for: filter)
        if selectionCount > 0 {
            Label("\(filter.title) (\(selectionCount))", systemImage: "checkmark")
        } else {
            Text(filter.title)
        }
    }

    private var searchProgressIndicator: some View {
        ProgressView()
            .progressViewStyle(.linear)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .opacity(searchStore.isUpdating ? 1 : 0)
            .accessibilityHidden(!searchStore.isUpdating)
            .accessibilityLabel(searchProgressAccessibilityLabel)
    }

    private var searchProgressAccessibilityLabel: String {
        guard let pendingSearchQuery = searchStore.pendingQuery, !pendingSearchQuery.isEmpty else {
            return "Updating \(library.title)"
        }
        return "Searching \(library.title) for \(pendingSearchQuery)"
    }

    private func refresh() {
        Task {
            await browserStore.load(
                library,
                searchQuery: searchStore.displayedQuery,
                browseOptions: searchStore.displayedOptions,
                forceRefresh: true
            )
        }
    }

    private func selectDefaultSort() {
        searchStore.selectSort(nil)
    }

    private func prefetchArtwork(after item: PlexMediaItem) async {
        let currentItems = items
        guard let itemIndex = currentItems.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        let requests = currentItems
            .dropFirst(itemIndex + 1)
            .prefix(6)
            .compactMap {
                PlexMediaPosterCard.prefetchRequest(
                    for: $0,
                    serverURL: connectionStore.resolvedServerURL,
                    token: settingsStore.trimmedServerToken,
                    clientContext: PlexClientContext(clientIdentifier: settingsStore.clientIdentifier),
                    spoilerPolicy: settingsStore.episodeSpoilerPolicy
                )
            }
        await artworkPrefetcher.prefetch(requests)
    }

    @ViewBuilder
    private func menuLabel(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

private struct LibraryBrowseTask: Equatable {
    let libraryID: String
    let query: String
    let options: PlexLibraryBrowseOptions
}

struct PlexMediaPosterCard: View {
    static let artworkWidth: CGFloat = 180
    static let standardGridColumns = [
        GridItem(.adaptive(minimum: artworkWidth, maximum: 205), spacing: 20)
    ]

    typealias ArtworkLayout = PlexMediaArtworkLayout

    let item: PlexMediaItem
    let settingsStore: PlexSettingsStore
    let serverURL: URL?
    var artworkLayout: ArtworkLayout = .automatic

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            PlexArtworkView(
                primaryImageURL: artworkURL,
                fallbackImageURL: nil,
                token: settingsStore.trimmedServerToken,
                clientContext: PlexClientContext(clientIdentifier: settingsStore.clientIdentifier),
                placeholderSymbol: placeholderSymbol,
                width: Self.artworkWidth,
                height: artworkHeight,
                cornerRadius: 12
            )
            .plexWatchedIndicator(isWatched: item.isWatched)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) {
                if let progress = item.progress {
                    ProgressView(value: progress)
                        .tint(.white)
                        .padding(8)
                        .accessibilityHidden(true)
                }
            }

            if let title = cardTitle {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
            }

            if let subtitle = cardSubtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.watchStateAccessibilityValue ?? "")
    }

    private var cardTitle: String? {
        switch item.type?.lowercased() {
        case "episode": item.grandparentTitle
        case "season": item.parentTitle
        default: item.title
        }
    }

    private var cardSubtitle: String? {
        switch item.type?.lowercased() {
        case "episode":
            return PlexEpisodeText.subtitle(season: item.parentIndex, episode: item.index, title: item.title)
        case "season":
            return item.title
        case "show":
            return nil
        default:
            return item.subtitle
        }
    }

    private var artworkURL: URL? {
        Self.artworkURL(
            for: item,
            serverURL: serverURL,
            artworkLayout: artworkLayout,
            spoilerPolicy: settingsStore.episodeSpoilerPolicy
        )
    }

    private var placeholderSymbol: String {
        spoilerPresentation.isProtected && artworkLayout == .automatic
            ? "eye.slash"
            : item.placeholderSymbol
    }

    private var artworkHeight: CGFloat {
        Self.artworkHeight(for: item, artworkLayout: artworkLayout)
    }

    static func prefetchRequest(
        for item: PlexMediaItem,
        serverURL: URL?,
        token: String,
        clientContext: PlexClientContext,
        artworkLayout: ArtworkLayout = .automatic,
        spoilerPolicy: PlexEpisodeSpoilerPolicy
    ) -> PlexArtworkPrefetchRequest? {
        guard let artworkURL = artworkURL(
            for: item,
            serverURL: serverURL,
            artworkLayout: artworkLayout,
            spoilerPolicy: spoilerPolicy
        ) else {
            return nil
        }

        let height = artworkHeight(for: item, artworkLayout: artworkLayout)
        return PlexArtworkPrefetchRequest(
            candidateURLs: [artworkURL],
            token: token,
            clientContext: clientContext,
            maximumPixelSize: Int(ceil(max(artworkWidth, height) * 2))
        )
    }

    private static func artworkURL(
        for item: PlexMediaItem,
        serverURL: URL?,
        artworkLayout: ArtworkLayout,
        spoilerPolicy: PlexEpisodeSpoilerPolicy
    ) -> URL? {
        guard let serverURL else {
            return nil
        }

        let artworkPath = artworkPath(
            for: item,
            artworkLayout: artworkLayout,
            spoilerPolicy: spoilerPolicy
        )
        return PlexURLBuilder.mediaURL(serverURL: serverURL, path: artworkPath)
    }

    private static func artworkPath(
        for item: PlexMediaItem,
        artworkLayout: ArtworkLayout,
        spoilerPolicy: PlexEpisodeSpoilerPolicy
    ) -> String? {
        guard artworkLayout != .automatic || !spoilerPolicy.hidesSpoilers(for: item) else { return nil }
        return PlexMediaArtworkPresentation(item: item, layout: artworkLayout).path
    }

    private var spoilerPresentation: PlexEpisodeSpoilerPresentation {
        PlexEpisodeSpoilerPresentation(
            item: item,
            policy: settingsStore.episodeSpoilerPolicy
        )
    }

    private static func artworkHeight(
        for item: PlexMediaItem,
        artworkLayout: ArtworkLayout
    ) -> CGFloat {
        switch PlexMediaArtworkPresentation(item: item, layout: artworkLayout).shape {
        case .poster: 270
        case .landscape: 101
        case .square: 180
        }
    }
}
