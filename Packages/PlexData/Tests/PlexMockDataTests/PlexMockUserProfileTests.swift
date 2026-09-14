import Foundation
import PlexMockData
import Testing

@Suite struct PlexMockUserProfileTests {
    private var user: [String: Any] {
        ["id": 11, "friendlyName": "Elliot", "username": "elliot", "email": "elliot@example.com",
         "avatar": "/avatar.png", "devices": [device]]
    }

    private var device: [String: Any] {
        ["id": 1, "title": "Iceweasel", "machineIdentifier": "elliot-browser",
         "platform": "Linux", "product": "Plex Web",
         "connection": ["remotePublicAddress": "203.0.113.24", "resolvedLocation": "Brooklyn, NY",
                        "local": false, "relayed": false, "secure": true]]
    }

    private func payload(users: [[String: Any]]? = nil, sessionDeviceID: Int = 1,
                         historyDeviceID: Int? = 1, authenticatedUserID: Int = 11) throws -> PlexMockServerPayload {
        var event: [String: Any] = ["historyKey": "history-1", "userID": 11, "mediaType": "movie",
                                     "mediaID": "movie-1", "viewedAtSecondsAgo": 100]
        event["deviceID"] = historyDeviceID
        let object: [String: Any] = [
            "authenticatedUserID": authenticatedUserID,
            "users": users ?? [user],
            "server": ["id": "server", "name": "Mock", "accessToken": "mock", "connections": []],
            "activeSessions": ["playing", "paused"].enumerated().map { index, state in
                ["sessionKey": "session-\(index)", "userID": 11, "deviceID": sessionDeviceID,
                 "state": state, "mediaType": "movie", "mediaID": "movie-1"] as [String: Any]
            },
            "historyEvents": [event], "libraries": [],
            "artwork": [["path": "/avatar.png", "resource": "avatar.png"]],
        ]
        return try JSONDecoder().decode(PlexMockServerPayload.self, from: JSONSerialization.data(withJSONObject: object))
    }

    @Test func identityAndDeviceAreSharedWhilePlaybackStateStaysIndependent() throws {
        let payload = try payload()
        try payload.validateProfiles()
        let user = try #require(payload.users.first)
        let device = try #require(user.devices.first)
        #expect(user.materialize().thumb == user.materializeUser().thumb)
        #expect(user.materializeAuthenticatedUser().thumb == user.avatar)
        #expect(user.materializeAuthenticatedUser().email == "elliot@example.com")
        #expect(user.materializeAuthenticatedUser().title == user.name)
        #expect(payload.activeSessions.map { device.materializePlayer(state: $0.state).state } == ["playing", "paused"])
        #expect(device.materializePlayer(state: "playing").title == "Iceweasel")
        #expect(device.materializePlayer(state: "playing").remotePublicAddress == "203.0.113.24")
        #expect(device.connection.sessionLocation == "wan")
        #expect(device.materializeHistoryDevice().id == payload.historyEvents.first?.deviceID)
        #expect(device.materializeHistoryDevice().platform == "Linux")
    }

    @Test func rejectsMissingAuthenticationAndActivityReferences() throws {
        #expect(throws: PlexMockServerPayload.ProfileError.self) { try payload(authenticatedUserID: 99).validateProfiles() }
        #expect(throws: PlexMockServerPayload.ProfileError.self) { try payload(sessionDeviceID: 99).validateProfiles() }
        #expect(throws: PlexMockServerPayload.ProfileError.self) { try payload(historyDeviceID: 99).validateProfiles() }
        try payload(historyDeviceID: nil).validateProfiles()
    }

    @Test func rejectsAnotherUsersDeviceAndDuplicateGlobalIdentities() throws {
        var otherDevice = device
        otherDevice["id"] = 2
        otherDevice["machineIdentifier"] = "other-browser"
        var otherUser = user
        otherUser["id"] = 12
        otherUser["devices"] = [otherDevice]
        #expect(throws: PlexMockServerPayload.ProfileError.self) {
            try payload(users: [user, otherUser], sessionDeviceID: 2).validateProfiles()
        }
        #expect(throws: PlexMockServerPayload.ProfileError.self) {
            try payload(users: [user, otherUser], historyDeviceID: 2).validateProfiles()
        }
        otherUser["devices"] = [device]
        #expect(throws: PlexMockServerPayload.ProfileError.self) { try payload(users: [user, otherUser]).validateProfiles() }
        #expect(throws: PlexMockServerPayload.ProfileError.self) { try payload(users: [user, user]).validateProfiles() }
        otherDevice["machineIdentifier"] = device["machineIdentifier"]
        otherUser["devices"] = [otherDevice]
        #expect(throws: PlexMockServerPayload.ProfileError.self) { try payload(users: [user, otherUser]).validateProfiles() }
    }

    @Test func rejectsMissingAvatarsAndConflictingIPLocations() throws {
        var changed = user
        changed["avatar"] = "/missing.png"
        #expect(throws: PlexMockServerPayload.ProfileError.self) { try payload(users: [changed]).validateProfiles() }
        var otherDevice = device
        otherDevice["id"] = 2
        otherDevice["machineIdentifier"] = "second-browser"
        otherDevice["connection"] = ["remotePublicAddress": "203.0.113.24", "resolvedLocation": "Paris, France"]
        changed = user
        changed["devices"] = [device, otherDevice]
        #expect(throws: PlexMockServerPayload.ProfileError.self) { try payload(users: [changed]).validateProfiles() }
    }

    @Test func profileRoundTripPreservesUnknownConnectionValues() throws {
        var user = try #require(payload().users.first)
        user.devices[0].connection = .init()
        let encoded = try JSONEncoder().encode(user)
        let decoded = try JSONDecoder().decode(PlexMockServerPayload.User.self, from: encoded)
        #expect(decoded == user)
        #expect(decoded.devices[0].connection.sessionLocation == nil)
        #expect(decoded.devices[0].materializePlayer(state: nil).secure == nil)
        #expect(decoded.devices[0].materializePlayer(state: nil).local == nil)
    }
    @Test func nameDrivesAllDisplayValuesAndFallsBackToUsernameWhenBlank() throws {
        var user = try #require(payload().users.first)
        for name in ["Baumer", "", "   ", nil] as [String?] {
            user.friendlyName = name
            let expected = name == "Baumer" ? "Baumer" : "elliot"
            #expect(user.materialize().name == expected)
            #expect(user.materializeUser().title == expected)
            #expect(user.materializeAuthenticatedUser().title == expected)
            #expect(user.materializeAuthenticatedUser().username == "elliot")
        }
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(user)) as? [String: Any])
        #expect(object["name"] == nil)
    }

}
