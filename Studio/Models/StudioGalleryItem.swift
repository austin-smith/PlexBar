import Foundation

struct StudioGalleryItem: Identifiable, Sendable {
    var id: String
    var title: String
    var subtitle: String
    var category: StudioCategory
    var recordID: String?
    var assetPath: String?
    var previewURL: URL?
    var ratio: Double
    var sortTitle: String?

    static func orderedByTitle(_ lhs: Self, _ rhs: Self) -> Bool {
        let order = (lhs.sortTitle ?? lhs.title).localizedStandardCompare(rhs.sortTitle ?? rhs.title)
        if order != .orderedSame { return order == .orderedAscending }
        let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
        if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
        return lhs.id < rhs.id
    }
}
