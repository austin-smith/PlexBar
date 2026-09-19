import Foundation

/// Contains only presentation data. Account tokens and authenticated URLs never cross this boundary.
public struct TVTopShelfSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var version = currentVersion
    public let serverIdentifier: String
    public let sections: [Section]

    public init(serverIdentifier: String, sections: [Section]) {
        self.serverIdentifier = serverIdentifier
        self.sections = sections
    }

    public struct Section: Codable, Equatable, Sendable {
        public let identifier: String
        public let title: String
        public let items: [Item]

        public init(identifier: String, title: String, items: [Item]) {
            self.identifier = identifier
            self.title = title
            self.items = items
        }
    }

    public struct Item: Codable, Equatable, Sendable {
        public enum Shape: String, Codable, Sendable {
            case poster
            case square
        }

        public let ratingKey: String
        public let title: String
        public let imageFilename: String
        public let shape: Shape
        public let playbackProgress: Double
        public let canPlay: Bool

        public init(
            ratingKey: String,
            title: String,
            imageFilename: String,
            shape: Shape,
            playbackProgress: Double,
            canPlay: Bool
        ) {
            self.ratingKey = ratingKey
            self.title = title
            self.imageFilename = imageFilename
            self.shape = shape
            self.playbackProgress = playbackProgress
            self.canPlay = canPlay
        }
    }
}
