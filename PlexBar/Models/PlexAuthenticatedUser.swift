import Foundation

struct PlexAuthenticatedUser: Decodable, Equatable, Identifiable {
    let id: Int
    let username: String
    let title: String?
    let email: String?
    let thumb: String?
    let friendlyName: String?
    let subscription: PlexAccountSubscription?
    let subscriptions: [PlexUserSubscription]
    let roles: [String]
    let entitlements: [String]

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

    init(
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

    init(from decoder: Decoder) throws {
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

    var displayName: String {
        title?.nilIfBlank ?? username
    }

    var displayEmail: String? {
        email?.nilIfBlank
    }

    var displayUsername: String? {
        let normalizedUsername = username.nilIfBlank
        guard let normalizedUsername,
              normalizedUsername != displayName else {
            return nil
        }

        return normalizedUsername
    }

    var hasPlexPass: Bool {
        subscription?.isEffectivePlexPass == true
            || subscriptions.contains(where: \.isEffectivePlexPass)
            || roles.contains(where: { $0.caseInsensitiveCompare("plexpass") == .orderedSame })
    }

    var hasDownloadsAccountEntitlement: Bool {
        let capabilities = Set(
            (subscription?.features ?? []) + roles + entitlements
        ).map { $0.lowercased() }

        return hasPlexPass
            || capabilities.contains("sync")
            || capabilities.contains("grandfather-sync")
    }
}

struct PlexAccountSubscription: Decodable, Equatable, Sendable {
    let active: Bool?
    let status: String?
    let plan: String?
    let features: [String]

    private enum CodingKeys: String, CodingKey {
        case active
        case status
        case plan
        case features
    }

    init(
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

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        active = values.decodePlexBoolIfPresent(forKey: .active)
        status = try values.decodeIfPresent(String.self, forKey: .status)
        plan = try values.decodeIfPresent(String.self, forKey: .plan)
        features = values.decodePlexStringListIfPresent(forKey: .features) ?? []
    }

    var isEffectivePlexPass: Bool {
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

struct PlexUserSubscriptions: Decodable, Equatable, Sendable {
    let subscription: [PlexUserSubscription]

    init(subscription: [PlexUserSubscription]) {
        self.subscription = subscription
    }

    init(from decoder: Decoder) throws {
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

struct PlexUserSubscription: Decodable, Equatable, Sendable {
    let type: String
    let state: String
    let mode: String?
    let active: Bool?
    let subscribedAt: String?

    var isEffectivePlexPass: Bool {
        type == "plexpass" && (state == "active" || state == "pending_cancellation")
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
