import Foundation

public struct PlexMediaChapter: Decodable, Equatable, Hashable, Sendable {
    public let id: String?
    public let index: Int?
    public let startTimeOffset: Int?
    public let endTimeOffset: Int?
    public let title: String?
    public let thumb: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case index
        case startTimeOffset
        case endTimeOffset
        case title
        case thumb
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = values.decodePlexStringIfPresent(forKey: .id)
        index = values.decodePlexIntIfPresent(forKey: .index)
        startTimeOffset = values.decodePlexIntIfPresent(forKey: .startTimeOffset)
        endTimeOffset = values.decodePlexIntIfPresent(forKey: .endTimeOffset)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        thumb = try values.decodeIfPresent(String.self, forKey: .thumb)
    }
}
