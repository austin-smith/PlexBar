import Foundation

public struct PlexMediaMarker: Decodable, Equatable, Hashable, Sendable {
    public let id: String?
    public let type: String
    public let startTimeOffset: Int?
    public let endTimeOffset: Int?
    public let isFinal: Bool?

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case startTimeOffset
        case endTimeOffset
        case isFinal = "final"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = values.decodePlexStringIfPresent(forKey: .id)
        type = try values.decode(String.self, forKey: .type)
        startTimeOffset = values.decodePlexIntIfPresent(forKey: .startTimeOffset)
        endTimeOffset = values.decodePlexIntIfPresent(forKey: .endTimeOffset)
        isFinal = values.decodePlexBoolIfPresent(forKey: .isFinal)
    }
}
