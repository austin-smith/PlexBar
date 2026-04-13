import Foundation

struct PlexAccount: Decodable, Identifiable, Equatable {
    let id: Int
    let name: String
    let thumb: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case thumb
    }
}
