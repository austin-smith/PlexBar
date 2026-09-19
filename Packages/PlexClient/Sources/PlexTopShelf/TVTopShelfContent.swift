#if os(tvOS)
import Foundation
import TVServices

public enum TVTopShelfContentBuilder {
    public static func make(snapshot: TVTopShelfSnapshot, cache: TVTopShelfCache) -> TVTopShelfSectionedContent? {
        guard snapshot.version == TVTopShelfSnapshot.currentVersion,
              !snapshot.serverIdentifier.isEmpty else { return nil }
        var seen: Set<String> = []
        let sections = snapshot.sections.compactMap { section -> TVTopShelfItemCollection<TVTopShelfSectionedItem>? in
            let items = section.items.compactMap { entry -> TVTopShelfSectionedItem? in
                guard TVTopShelfRoute.isValidRatingKey(entry.ratingKey),
                      let url = cache.imageURL(filename: entry.imageFilename),
                      FileManager.default.fileExists(atPath: url.path) else { return nil }
                let route = TVTopShelfRoute(
                    action: .display, serverIdentifier: snapshot.serverIdentifier, ratingKey: entry.ratingKey
                )
                guard seen.insert(route.url.absoluteString).inserted else { return nil }
                let item = TVTopShelfSectionedItem(identifier: route.url.absoluteString)
                item.title = entry.title
                item.imageShape = entry.shape == .poster ? .poster : .square
                item.setImageURL(url, for: .screenScale1x)
                item.setImageURL(url, for: .screenScale2x)
                item.playbackProgress = entry.playbackProgress.isFinite ? min(max(entry.playbackProgress, 0), 1) : 0
                item.displayAction = TVTopShelfAction(url: route.url)
                if entry.canPlay {
                    item.playAction = TVTopShelfAction(url: TVTopShelfRoute(
                        action: .play, serverIdentifier: snapshot.serverIdentifier, ratingKey: entry.ratingKey
                    ).url)
                }
                return item
            }
            guard !items.isEmpty else { return nil }
            let collection = TVTopShelfItemCollection(items: items)
            collection.title = section.title
            return collection
        }
        return sections.isEmpty ? nil : TVTopShelfSectionedContent(sections: sections)
    }
}
#endif
