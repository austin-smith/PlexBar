import Foundation

public struct TVTopShelfRoute: Equatable, Sendable {
    public enum Action: String, Sendable {
        case display
        case play
    }

    public let action: Action
    public let serverIdentifier: String
    public let ratingKey: String

    public init(action: Action, serverIdentifier: String, ratingKey: String) {
        self.action = action
        self.serverIdentifier = serverIdentifier
        self.ratingKey = ratingKey
    }

    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "plexbar-tv", components.host == "topshelf",
              components.user == nil, components.password == nil,
              components.port == nil, components.fragment == nil,
              let action = Action(rawValue: String(components.path.dropFirst())),
              components.path == "/\(action.rawValue)",
              let query = components.queryItems, query.count == 2,
              query.filter({ $0.name == "server" }).count == 1,
              query.filter({ $0.name == "item" }).count == 1,
              let server = query.first(where: { $0.name == "server" })?.value,
              !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let key = query.first(where: { $0.name == "item" })?.value,
              Self.isValidRatingKey(key) else { return nil }
        self.init(action: action, serverIdentifier: server, ratingKey: key)
    }

    public static func isValidRatingKey(_ key: String) -> Bool {
        !key.isEmpty && key.utf8.allSatisfy { (48...57).contains($0) }
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = "plexbar-tv"
        components.host = "topshelf"
        components.path = "/\(action.rawValue)"
        components.queryItems = [
            URLQueryItem(name: "server", value: serverIdentifier),
            URLQueryItem(name: "item", value: ratingKey)
        ]
        return components.url!
    }
}
