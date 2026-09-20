import Foundation

public struct PlexAccount: Decodable, Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let thumb: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case thumb
    }

    public init(
        id: Int,
        name: String,
        thumb: String? = nil
    ) {
        self.id = id
        self.name = name
        self.thumb = thumb
    }
}

public struct PlexHistoryDevice: Decodable, Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let platform: String?

    public var displayLine: String? {
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

    public init(
        id: Int,
        name: String,
        platform: String? = nil
    ) {
        self.id = id
        self.name = name
        self.platform = platform
    }
}

public struct PlexHistoryIdentityDirectory: Equatable, Sendable {
    public let accounts: [PlexAccount]
    public let devices: [PlexHistoryDevice]

    public init(
        accounts: [PlexAccount],
        devices: [PlexHistoryDevice]
    ) {
        self.accounts = accounts
        self.devices = devices
    }
}
