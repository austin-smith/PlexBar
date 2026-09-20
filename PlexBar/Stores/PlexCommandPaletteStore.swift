import PlexClientKit
import Foundation
import Observation
import PlexModels

@MainActor
@Observable
final class PlexCommandPaletteStore {
    private(set) var isPresented = false
    private(set) var isPresentationRequested = false
    private(set) var results: [PlexPaletteResult] = []
    private(set) var selectedID: PlexPaletteResult.ID?
    private(set) var isSearching = false
    private(set) var searchError: String?
    private(set) var actionError: String?
    private(set) var isPreparingPlayback = false
    private(set) var hubs: [PlexHub] = []
    private(set) var recentItems: [PlexMediaItem] = []
    private(set) var canSearch = false
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            restartSearch()
        }
    }

    @ObservationIgnored var requestPresentation: (() -> Void)?
    @ObservationIgnored private var commands: [PlexPaletteCommand] = []
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    @ObservationIgnored private var load: ((String) async throws -> [PlexHub])?
    @ObservationIgnored private var scope: String?
    @ObservationIgnored private var suggestions: [PlexMediaItem] = []
    @ObservationIgnored private var libraries: [PlexLibrary] = []
    @ObservationIgnored private var downloads: [PlexOfflineMedia] = []
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var hasExplicitSelection = false
    private let debounce: Duration

    init(debounce: Duration = .milliseconds(200)) { self.debounce = debounce }

    var searchQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var selectedResult: PlexPaletteResult? { results.first { $0.id == selectedID && $0.isEnabled } }
    var selectedCommand: PlexPaletteCommand? {
        guard case .command(let command) = selectedResult?.content else { return nil }
        return command
    }

    func configure(
        scope: String, canSearch: Bool, suggestions: [PlexMediaItem], libraries: [PlexLibrary],
        downloads: [PlexOfflineMedia], load: @escaping (String) async throws -> [PlexHub]
    ) {
        let changedScope = self.scope != scope
        let availabilityChanged = self.canSearch != canSearch
        if changedScope {
            if self.scope != nil { dismiss() }
            recentItems = []
            self.scope = scope
        }
        self.canSearch = canSearch
        self.suggestions = suggestions
        self.libraries = libraries
        self.downloads = downloads
        self.load = load
        if availabilityChanged, isPresented { restartSearch() }
        else { rebuildResults() }
    }

    func request() { isPresentationRequested = true; requestPresentation?() }

    func present() {
        guard !isPresented else { return }
        isPresentationRequested = false
        isPresented = true
        if query.isEmpty { restartSearch() }
        else { query = "" }
    }

    func dismiss() {
        revision += 1
        searchTask?.cancel()
        playbackTask?.cancel()
        searchTask = nil
        playbackTask = nil
        isSearching = false
        isPreparingPlayback = false
        isPresentationRequested = false
        isPresented = false
    }

    func updateCommands(_ commands: [PlexPaletteCommand]) {
        guard self.commands != commands else { return }
        self.commands = commands
        rebuildResults()
    }

    func select(_ id: PlexPaletteResult.ID) {
        guard results.contains(where: { $0.id == id && $0.isEnabled }) else { return }
        selectedID = id
        hasExplicitSelection = true
    }

    func moveSelection(by offset: Int) {
        let enabled = results.filter(\.isEnabled)
        guard !enabled.isEmpty else { selectedID = nil; return }
        let current = enabled.firstIndex { $0.id == selectedID } ?? (offset > 0 ? -1 : enabled.count)
        select(enabled[min(max(current + offset, 0), enabled.count - 1)].id)
    }

    func remember(_ item: PlexMediaItem) {
        recentItems.removeAll { $0.ratingKey == item.ratingKey }
        recentItems.insert(item, at: 0)
        recentItems = Array(recentItems.prefix(6))
    }

    func clearRecents() { recentItems = []; rebuildResults() }
    func retry() { restartSearch() }

    func preparePlayback(
        _ result: PlexPaletteResult,
        prepare: @escaping () async throws -> PlexPlaybackPresentation,
        present: @escaping (PlexPlaybackPresentation) -> Void
    ) {
        guard isPresented, !isPreparingPlayback, result.canPlay,
              results.contains(where: { $0.id == result.id }) else { return }
        actionError = nil
        isPreparingPlayback = true
        let revision = revision
        playbackTask = Task { [weak self] in
            do {
                let presentation = try await prepare()
                guard let self, self.isPresented, self.revision == revision, !Task.isCancelled else { return }
                self.isPreparingPlayback = false
                if case .media(let item, _) = result.content { self.remember(item) }
                present(presentation)
            } catch {
                guard let self, self.revision == revision, !Task.isCancelled else { return }
                self.isPreparingPlayback = false
                self.actionError = error.localizedDescription
            }
        }
    }

    private func restartSearch() {
        revision += 1
        searchTask?.cancel()
        playbackTask?.cancel()
        isPreparingPlayback = false
        hubs = []
        searchError = nil
        actionError = nil
        selectedID = nil
        hasExplicitSelection = false
        isSearching = isPresented && !searchQuery.isEmpty && canSearch && load != nil
        rebuildResults()
        guard isSearching, let load else { return }
        let revision = revision
        let query = searchQuery
        searchTask = Task { [weak self, debounce] in
            do {
                try await Task.sleep(for: debounce)
                try Task.checkCancellation()
                let hubs = try await load(query)
                guard let self, self.revision == revision, self.isPresented, !Task.isCancelled else { return }
                self.hubs = hubs
                self.isSearching = false
                self.rebuildResults()
            } catch {
                guard let self, self.revision == revision, self.isPresented, !Task.isCancelled else { return }
                self.searchError = error.localizedDescription
                self.isSearching = false
                self.rebuildResults()
            }
        }
    }

    var hasMatchingResults: Bool {
        results.contains { result in
            if case .allResults = result.content { return false }
            return true
        }
    }

    private func rebuildResults() {
        let matches = PlexPaletteCommand.matching(commands, query: searchQuery)
        let visibleCommands = searchQuery.isEmpty ? Array(matches.prefix(4)) : matches
        let commandResults = visibleCommands.map { PlexPaletteResult(content: .command($0), group: "Commands") }
        var entries: [PlexPaletteResult] = []
        if searchQuery.isEmpty {
            var seen = Set<String>()
            for (group, items) in [("Recently Opened", Array(recentItems.prefix(3))),
                                   ("Continue Watching", Array(suggestions.prefix(3)))] {
                for item in items where seen.insert(item.ratingKey).inserted {
                    entries.append(.media(item, group: group, libraries: libraries, downloads: downloads))
                }
            }
            entries += commandResults
        } else {
            var media = PlexPaletteResult.mediaResults(hubs: hubs, query: searchQuery, libraries: libraries, downloads: downloads)
            var mediaIDs = Set(media.map(\.id))
            for download in downloads where PlexPaletteResult.matches(download.item, query: searchQuery)
                && mediaIDs.insert(.media(download.item.ratingKey)).inserted {
                media.append(.media(download.item, group: "Library", libraries: libraries, downloads: [download]))
            }
            // Exact titles stay first, including downloaded titles. A mixed search
            // previews four library items so matching commands stay discoverable.
            let exactMedia = media.filter { $0.matchesTitleExactly(searchQuery) }
            let otherMedia = media.filter { !$0.matchesTitleExactly(searchQuery) }
            media = Array((exactMedia + otherMedia).prefix(matches.isEmpty ? 12 : 4)).map {
                PlexPaletteResult(content: $0.content, group: "Library", libraryTitle: $0.libraryTitle)
            }
            let commandsLead = matches.contains { $0.matchesExactly(searchQuery) }
                && !media.contains { $0.matchesTitleExactly(searchQuery) }
            entries = commandsLead ? commandResults + media : media + commandResults
            if canSearch { entries.append(.init(content: .allResults(searchQuery), group: "Search")) }
        }
        results = entries
        if hasExplicitSelection, entries.contains(where: { $0.id == selectedID && $0.isEnabled }) { return }
        // Wait for library results before choosing a default action. Explicit
        // keyboard or mouse selection remains stable as those results arrive.
        let firstAction = entries.first { entry in
            guard entry.isEnabled else { return false }
            if case .allResults = entry.content { return false }
            return true
        }
        selectedID = isSearching ? nil : (firstAction ?? entries.first(where: \.isEnabled))?.id
        hasExplicitSelection = false
    }
}
