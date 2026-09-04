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

struct PlexHistoryDevice: Decodable, Identifiable, Equatable {
    let id: Int
    let name: String
    let platform: String?

    var displayLine: String? {
        let values = [name.nilIfBlank, platform?.nilIfBlank]
            .compactMap { $0 }
            .reduce(into: [String]()) { result, value in
                guard
                    !result.contains(where: {
                        $0.localizedCaseInsensitiveCompare(value) == .orderedSame
                    })
                else {
                    return
                }
                result.append(value)
            }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }
}

struct PlexHistoryIdentityDirectory: Equatable {
    let accounts: [PlexAccount]
    let devices: [PlexHistoryDevice]
}
