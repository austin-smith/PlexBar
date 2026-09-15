import Foundation
import PlexModels

extension PlexMockServerPayload {
    /// Validate authoring references before either app materializes Plex responses.
    public func validateProfiles() throws {
        var userIDs: Set<Int> = []
        var deviceIDs: Set<Int> = []
        var machineIdentifiers: Set<String> = []
        var locationsByIP: [String: String] = [:]
        for user in users {
            guard userIDs.insert(user.id).inserted else {
                throw ProfileError("Duplicate user ID \(user.id).")
            }
            guard user.username.nilIfBlank != nil else {
                throw ProfileError("User \(user.id) needs a username.")
            }
            for device in user.devices {
                guard deviceIDs.insert(device.id).inserted else {
                    throw ProfileError("Duplicate device ID \(device.id). Device IDs must be unique across users.")
                }
                guard device.title.nilIfBlank != nil, device.machineIdentifier.nilIfBlank != nil else {
                    throw ProfileError("Device \(device.id) needs a name and machine identifier.")
                }
                guard machineIdentifiers.insert(device.machineIdentifier).inserted else {
                    throw ProfileError("Duplicate machine identifier \(device.machineIdentifier).")
                }
                if let location = device.connection.resolvedLocation?.nilIfBlank {
                    guard let ip = device.connection.remotePublicAddress?.nilIfBlank else {
                        throw ProfileError("Device \(device.id) needs a public IP address to resolve its location.")
                    }
                    if let existing = locationsByIP[ip], existing != location {
                        throw ProfileError("Public IP \(ip) has conflicting mock locations.")
                    }
                    locationsByIP[ip] = location
                }
            }
        }
        guard userIDs.contains(authenticatedUserID) else {
            throw ProfileError("Authenticated user \(authenticatedUserID) does not exist.")
        }
        let artworkPaths = Set(artwork.map(\.path))
        for user in users {
            if let avatar = user.avatar, !artworkPaths.contains(avatar) {
                throw ProfileError("User \(user.id) has an unregistered avatar: \(avatar).")
            }
        }
        let usersByID = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
        func validateDevice(_ deviceID: Int?, userID: Int, context: String) throws {
            guard let user = usersByID[userID] else {
                throw ProfileError("\(context) references missing user \(userID).")
            }
            if let deviceID, !user.devices.contains(where: { $0.id == deviceID }) {
                throw ProfileError("\(context) references device \(deviceID), which does not belong to user \(userID).")
            }
        }
        var sessionKeys: Set<String> = []
        for session in activeSessions {
            guard session.sessionKey.nilIfBlank != nil, sessionKeys.insert(session.sessionKey).inserted else {
                throw ProfileError("Active session keys must be present and unique.")
            }
            try validateDevice(session.deviceID, userID: session.userID, context: "Session \(session.sessionKey)")
        }
        for event in historyEvents {
            try validateDevice(event.deviceID, userID: event.userID, context: "History \(event.historyKey)")
        }
    }

    public struct ProfileError: LocalizedError, Sendable {
        public let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
