import Foundation

/// Contains only presentation data. Account tokens and authenticated URLs never cross this boundary.
struct TVTopShelfSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1
    var version = currentVersion
    let serverIdentifier: String
    let sections: [Section]

    struct Section: Codable, Equatable, Sendable {
        let identifier: String
        let title: String
        let items: [Item]
    }

    struct Item: Codable, Equatable, Sendable {
        enum Shape: String, Codable, Sendable {
            case poster
            case square
        }

        let ratingKey: String
        let title: String
        let imageFilename: String
        let shape: Shape
        let playbackProgress: Double
        let canPlay: Bool
    }
}
