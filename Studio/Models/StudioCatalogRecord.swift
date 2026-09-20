import Foundation

struct StudioCatalogRecord: Codable, Equatable, Identifiable, Sendable {
    var sources: [String]
    var addedAtSecondsAgo: Int
    var relatedIDs: [String]
    var extraIDs: [String]
    var metadata: StudioJSON

    var id: String { metadata["ratingKey"]?.string ?? "" }
    var title: String { metadata["title"]?.string ?? "Untitled" }
    var sortTitle: String {
        if let explicit = metadata["titleSort"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return explicit
        }
        return title
    }
    var type: String { metadata["type"]?.string ?? "" }
    var parentID: String? { metadata["parentRatingKey"]?.string }
    var isTitle: Bool { ["movie", "show", "album"].contains(type) }
    var subtitle: String {
        [metadata["parentTitle"]?.string, metadata["year"]?.integer.map(String.init)]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
