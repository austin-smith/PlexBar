import Foundation
import Observation

@MainActor
@Observable
final class TVHubBrowseStore {
    private(set) var items: [PlexMediaItem] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var hasMore = false
    private var nextOffset = 0
    private var identity: Identity?
    private var requestID: UUID?
    private var loadedFirstPage = false
    private let videoOnly: Bool

    init(videoOnly: Bool = false) {
        self.videoOnly = videoOnly
    }

    private func includedItems(_ items: [PlexMediaItem]) -> [PlexMediaItem] {
        videoOnly ? TVHomeContent.videoItems(items) : items
    }

    func load(hub: PlexHub, using store: TVAppStore, refresh: Bool = false) async {
        let identity = Identity(hub: hub, connection: store.connection)
        if self.identity == identity, !refresh, loadedFirstPage || isLoading { return }
        self.identity = identity
        requestID = nil
        items = includedItems(hub.metadata)
        nextOffset = 0
        loadedFirstPage = false
        hasMore = false
        await fetch(hub: hub, using: store)
    }

    func loadMore(hub: PlexHub, using store: TVAppStore, currentItem: PlexMediaItem? = nil) async {
        guard !isLoading, hasMore,
              identity == Identity(hub: hub, connection: store.connection),
              currentItem == nil || items.last?.id == currentItem?.id else { return }
        await fetch(hub: hub, using: store)
    }

    func retry(hub: PlexHub, using store: TVAppStore) async {
        if loadedFirstPage {
            await loadMore(hub: hub, using: store)
        } else {
            await load(hub: hub, using: store)
        }
    }

    func visibleItems(hub: PlexHub, connection: TVPlexConnection?) -> [PlexMediaItem] {
        identity == Identity(hub: hub, connection: connection) ? items : includedItems(hub.metadata)
    }

    /// Extend the existing collection as its trailing cards appear. Keep preview
    /// identities and their order intact so pagination never replaces the focus target.
    func loadInline(hub: PlexHub, using store: TVAppStore, after item: PlexMediaItem) async {
        let expected = Identity(hub: hub, connection: store.connection)
        guard hub.key?.nilIfBlank != nil,
              visibleItems(hub: hub, connection: store.connection).suffix(3).contains(where: { $0.id == item.id })
        else { return }
        if identity != expected || !loadedFirstPage {
            guard identity != expected || (!isLoading && errorMessage == nil),
                  hub.more || (hub.totalSize ?? hub.metadata.count) > hub.metadata.count else { return }
            await load(hub: hub, using: store)
        }
        // A page can overlap the preview or the previous page. Continue through
        // those server rows until this card has more content ahead of it.
        while identity == expected, store.connection == expected.connection, !Task.isCancelled, !isLoading,
              loadedFirstPage, hasMore, errorMessage == nil,
              items.suffix(3).contains(where: { $0.id == item.id }) {
            await loadMore(hub: hub, using: store)
        }
    }

    private func fetch(hub: PlexHub, using store: TVAppStore) async {
        let id = UUID()
        requestID = id
        isLoading = true
        errorMessage = nil
        defer {
            if requestID == id { isLoading = false; requestID = nil }
        }
        guard let path = hub.key?.nilIfBlank else {
            items = includedItems(hub.metadata)
            loadedFirstPage = true
            return
        }
        do {
            let page = try await store.hubPage(path: path, start: nextOffset)
            guard requestID == id, !Task.isCancelled else { return }
            let endOffset = page.offset + page.items.count
            guard page.items.isEmpty || endOffset > nextOffset else {
                throw PlexAPIError.invalidResponse
            }
            var seen = Set(items.map(\.id))
            items.append(contentsOf: includedItems(page.items).filter { seen.insert($0.id).inserted })
            nextOffset = endOffset
            loadedFirstPage = true
            // Offset is measured in server rows, not deduplicated cards.
            hasMore = !page.items.isEmpty && endOffset < (page.totalSize ?? hub.totalSize ?? endOffset)
        } catch is CancellationError {
            return
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    struct Identity: Equatable {
        let hub: PlexHub
        let connection: TVPlexConnection?
    }
}
