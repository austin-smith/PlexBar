import Foundation

public struct PlexAuthenticatedUser: Decodable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let username: String
    public let title: String?
    public let email: String?
    public let thumb: String?
    public let friendlyName: String?
    public let subscription: PlexAccountSubscription?
    public let subscriptions: [PlexUserSubscription]
    public let roles: [String]
    public let entitlements: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case title
        case email
        case thumb
        case friendlyName
        case subscription
        case subscriptions
        case roles
        case entitlements
    }

    public init(
        id: Int,
        username: String,
        title: String?,
        email: String?,
        thumb: String?,
        friendlyName: String?,
        subscription: PlexAccountSubscription? = nil,
        subscriptions: [PlexUserSubscription] = [],
        roles: [String] = [],
        entitlements: [String] = []
    ) {
        self.id = id
        self.username = username
        self.title = title
        self.email = email
        self.thumb = thumb
        self.friendlyName = friendlyName
        self.subscription = subscription
        self.subscriptions = subscriptions
        self.roles = roles
        self.entitlements = entitlements
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        username = try values.decode(String.self, forKey: .username)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        email = try values.decodeIfPresent(String.self, forKey: .email)
        thumb = try values.decodeIfPresent(String.self, forKey: .thumb)
        friendlyName = try values.decodeIfPresent(String.self, forKey: .friendlyName)
        subscription = try values.decodeIfPresent(PlexAccountSubscription.self, forKey: .subscription)
        subscriptions = try values.decodeIfPresent(
            PlexUserSubscriptions.self,
            forKey: .subscriptions
        )?.subscription ?? []
        roles = values.decodePlexStringListIfPresent(forKey: .roles) ?? []
        entitlements = values.decodePlexStringListIfPresent(forKey: .entitlements) ?? []
    }

    public var displayName: String {
        title?.nilIfBlank ?? username
    }

    public var displayEmail: String? {
        email?.nilIfBlank
    }

    public var displayUsername: String? {
        let normalizedUsername = username.nilIfBlank
        guard let normalizedUsername,
              normalizedUsername != displayName else {
            return nil
        }

        return normalizedUsername
    }

    public var hasPlexPass: Bool {
        subscription?.isEffectivePlexPass == true
            || subscriptions.contains(where: \.isEffectivePlexPass)
            || roles.contains(where: { $0.caseInsensitiveCompare("plexpass") == .orderedSame })
    }

    public var hasDownloadsAccountEntitlement: Bool {
        let capabilities = Set(
            (subscription?.features ?? []) + roles + entitlements
        ).map { $0.lowercased() }

        return hasPlexPass
            || capabilities.contains("sync")
            || capabilities.contains("grandfather-sync")
    }
}

public struct PlexAccountSubscription: Decodable, Equatable, Sendable {
    public let active: Bool?
    public let status: String?
    public let plan: String?
    public let features: [String]

    private enum CodingKeys: String, CodingKey {
        case active
        case status
        case plan
        case features
    }

    public init(
        active: Bool?,
        status: String?,
        plan: String?,
        features: [String]
    ) {
        self.active = active
        self.status = status
        self.plan = plan
        self.features = features
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        active = values.decodePlexBoolIfPresent(forKey: .active)
        status = try values.decodeIfPresent(String.self, forKey: .status)
        plan = try values.decodeIfPresent(String.self, forKey: .plan)
        features = values.decodePlexStringListIfPresent(forKey: .features) ?? []
    }

    public var isEffectivePlexPass: Bool {
        guard active == true else { return false }
        if let normalizedStatus = status?.nilIfBlank?.lowercased(),
           normalizedStatus != "active",
           normalizedStatus != "pending_cancellation" {
            return false
        }

        let normalizedFeatures = Set(features.map { $0.lowercased() })
        return normalizedFeatures.contains("plexpass") || normalizedFeatures.contains("pass")
    }
}

public struct PlexUserSubscriptions: Decodable, Equatable, Sendable {
    public let subscription: [PlexUserSubscription]

    public init(subscription: [PlexUserSubscription]) {
        self.subscription = subscription
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        subscription = try values.decodeIfPresent(
            [PlexUserSubscription].self,
            forKey: .subscription
        ) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case subscription
    }
}

public struct PlexUserSubscription: Decodable, Equatable, Sendable {
    public let type: String
    public let state: String
    public let mode: String?
    public let active: Bool?
    public let subscribedAt: String?

    public var isEffectivePlexPass: Bool {
        type == "plexpass" && (state == "active" || state == "pending_cancellation")
    }

    public init(
        type: String,
        state: String,
        mode: String? = nil,
        active: Bool? = nil,
        subscribedAt: String? = nil
    ) {
        self.type = type
        self.state = state
        self.mode = mode
        self.active = active
        self.subscribedAt = subscribedAt
    }
}

private extension KeyedDecodingContainer {
    func decodePlexStringListIfPresent(forKey key: Key) -> [String]? {
        if let values = try? decodeIfPresent([String].self, forKey: key) {
            return values
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return nil
    }
}
