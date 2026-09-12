import Foundation
import ImageIO
import os
import TVServices

@MainActor
final class TVTopShelfPublisher {
    private let cache: @Sendable () throws -> TVTopShelfCache
    private let notify: @MainActor () -> Void
    private var task: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.crapshack.PlexBar.tv", category: "TopShelf")

    init(
        cache: @escaping @Sendable () throws -> TVTopShelfCache = { try .shared() },
        notify: @escaping @MainActor () -> Void = { TVTopShelfContentProvider.topShelfContentDidChange() }
    ) {
        self.cache = cache
        self.notify = notify
    }

    func clear() {
        task?.cancel()
        task = nil
        do {
            try cache().clear()
        } catch {
            logger.error("Unable to clear Top Shelf: \(error.localizedDescription, privacy: .public)")
        }
        notify()
    }

    func publish(hubs: [PlexHub], connection: TVPlexConnection, client: TVPlexClient) {
        task?.cancel()
        logger.debug("Preparing Top Shelf from Plex hubs: \(hubs.map(\.hubIdentifier).joined(separator: ","), privacy: .public)")
        let selection = TVTopShelfSelection(hubs: hubs)
        task = Task {
            do {
                let cache = try cache()
                var sections: [TVTopShelfSnapshot.Section] = []
                for section in selection.sections {
                    let entries = await PlexBoundedConcurrentMap.compactMap(section.items, maximumConcurrentTasks: 4) { item in
                        guard !Task.isCancelled else { return nil as (PlexMediaItem, Data)? }
                        guard let path = TVTopShelfSelection.artworkPath(for: item) else { return nil as (PlexMediaItem, Data)? }
                        let shape = TVTopShelfSelection.shape(for: item)
                        let size = TVTopShelfSectionedContent.imageSize(for: shape == .poster ? .poster : .square)
                        do {
                            let data = try await client.fetchArtworkData(
                                path: path, width: Int(size.width * 2), height: Int(size.height * 2),
                                connection: connection, timeoutInterval: 10
                            )
                            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                                  CGImageSourceGetCount(source) > 0 else { throw TVPlexError.invalidResponse }
                            return (item, data)
                        } catch {
                            guard !Task.isCancelled else { return nil }
                            // A failed image is omitted; never hand TVServices a broken or authenticated URL.
                            Logger(subsystem: "com.crapshack.PlexBar.tv", category: "TopShelf")
                                .error("Top Shelf artwork failed for item \(item.ratingKey, privacy: .public): \(error.localizedDescription, privacy: .private)")
                            return nil
                        }
                    }
                    try Task.checkCancellation()
                    let items = try entries.map { item, data in
                        return TVTopShelfSnapshot.Item(
                            ratingKey: item.ratingKey, title: TVTopShelfSelection.title(for: item),
                            imageFilename: try cache.storeImage(data), shape: TVTopShelfSelection.shape(for: item),
                            playbackProgress: TVTopShelfSelection.progress(for: item), canPlay: item.tvCanStartPlayback
                        )
                    }
                    if !items.isEmpty {
                        sections.append(.init(identifier: section.identifier, title: section.title, items: items))
                    }
                }
                // No suspension between cancellation check and commit: a cleared session cannot republish.
                try Task.checkCancellation()
                let snapshot = TVTopShelfSnapshot(serverIdentifier: connection.serverIdentifier, sections: sections)
                try cache.write(snapshot)
                notify()
                try cache.pruneImages(keeping: snapshot)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Unable to publish Top Shelf: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func waitForPublication() async {
        await task?.value
    }
}
