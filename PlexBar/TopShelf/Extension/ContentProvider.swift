import PlexTopShelf
import os
import TVServices

final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        do {
            let cache = try TVTopShelfCache.shared()
            guard let snapshot = try cache.read() else { return nil }
            return TVTopShelfContentBuilder.make(snapshot: snapshot, cache: cache)
        } catch {
            Logger(subsystem: "com.crapshack.PlexBar.tv.topshelf", category: "TopShelf")
                .error("Unable to load Top Shelf: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
