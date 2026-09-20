@testable import PlexClientKit
import PlexModels
import Foundation
import Testing
@testable import PlexBar

@Suite(.serialized)
struct PlexDownloadAuthorizationTests {
    @Test func accountDownloadsEntitlementUsesEffectivePlexPassSubscriptionStates() throws {
        let activeUser = try decodeUser(subscriptionType: "plexpass", state: "active")
        let cancelingUser = try decodeUser(
            subscriptionType: "plexpass",
            state: "pending_cancellation"
        )
        let canceledUser = try decodeUser(subscriptionType: "plexpass", state: "canceled")
        let remotePassUser = try decodeUser(subscriptionType: "remotewatchpass", state: "active")

        #expect(activeUser.hasDownloadsAccountEntitlement)
        #expect(cancelingUser.hasDownloadsAccountEntitlement)
        #expect(!canceledUser.hasDownloadsAccountEntitlement)
        #expect(!remotePassUser.hasDownloadsAccountEntitlement)
    }

    @Test func missingSubscriptionsDoesNotInventAnAccountEntitlement() throws {
        let user = try JSONDecoder().decode(
            PlexAuthenticatedUser.self,
            from: Data(#"{"id":42,"username":"test-user"}"#.utf8)
        )

        #expect(user.subscriptions.isEmpty)
        #expect(!user.hasDownloadsAccountEntitlement)
    }

    @Test func currentAccountSubscriptionFeaturesAuthorizeDownloads() throws {
        let user = try JSONDecoder().decode(
            PlexAuthenticatedUser.self,
            from: Data(#"""
            {
              "id": 42,
              "username": "test-user",
              "subscription": {
                "active": 1,
                "status": "Active",
                "plan": "lifetime",
                "features": ["downloads-gating", "sync"]
              },
              "roles": ["plexpass"],
              "entitlements": []
            }
            """#.utf8)
        )

        #expect(user.subscription?.active == true)
        #expect(user.subscription?.features.contains("sync") == true)
        #expect(user.hasPlexPass)
        #expect(user.hasDownloadsAccountEntitlement)
    }

    @Test func grandfatherSyncCapabilityAuthorizesDownloadsWithoutActiveSubscription() throws {
        let user = try JSONDecoder().decode(
            PlexAuthenticatedUser.self,
            from: Data(#"""
            {
              "id": 42,
              "username": "test-user",
              "subscription": {
                "active": 0,
                "status": "Inactive",
                "features": []
              },
              "entitlements": ["grandfather-sync"]
            }
            """#.utf8)
        )

        #expect(!user.hasPlexPass)
        #expect(user.hasDownloadsAccountEntitlement)
    }

    @Test func activeSubscriptionWithoutDownloadCapabilityIsNotTreatedAsPlexPass() throws {
        let user = try JSONDecoder().decode(
            PlexAuthenticatedUser.self,
            from: Data(#"""
            {
              "id": 42,
              "username": "test-user",
              "subscription": {
                "active": 1,
                "status": "Active",
                "plan": "remote-watch",
                "features": ["remote-watch"]
              }
            }
            """#.utf8)
        )

        #expect(!user.hasPlexPass)
        #expect(!user.hasDownloadsAccountEntitlement)
    }

    @Test func providerCapabilitiesDecodeServerPermissionAndDownloadFlavorIndependently() throws {
        let endpoints = try providerEndpoints(allowSync: "true", includeDownloadFeature: true)

        #expect(endpoints.serverAllowsSync == true)
        #expect(endpoints.supportsDownloadSubscriptions)
    }

    @Test func downloadAuthorizationRequiresEveryPublishedGate() throws {
        let user = try decodeUser(subscriptionType: "plexpass", state: "active")
        let noPassUser = try decodeUser(subscriptionType: "plexpass", state: "lapsed")
        let authorizedEndpoints = try providerEndpoints(
            allowSync: "true",
            includeDownloadFeature: true
        )
        let deniedEndpoints = try providerEndpoints(
            allowSync: "false",
            includeDownloadFeature: true
        )
        let unknownPermissionEndpoints = try providerEndpoints(
            allowSync: nil,
            includeDownloadFeature: true
        )
        let unsupportedProviderEndpoints = try providerEndpoints(
            allowSync: "true",
            includeDownloadFeature: false
        )

        #expect(PlexDownloadAuthorization(
            user: user,
            library: downloadLibrary(),
            providerEndpoints: authorizedEndpoints
        ).isAuthorized)
        #expect(!PlexDownloadAuthorization(
            user: noPassUser,
            library: downloadLibrary(),
            providerEndpoints: authorizedEndpoints
        ).isAuthorized)
        #expect(!PlexDownloadAuthorization(
            user: user,
            library: downloadLibrary(),
            providerEndpoints: deniedEndpoints
        ).isAuthorized)
        #expect(!PlexDownloadAuthorization(
            user: user,
            library: downloadLibrary(),
            providerEndpoints: unknownPermissionEndpoints
        ).isAuthorized)
        #expect(!PlexDownloadAuthorization(
            user: user,
            library: downloadLibrary(),
            providerEndpoints: unsupportedProviderEndpoints
        ).isAuthorized)
        #expect(!PlexDownloadAuthorization(
            user: user,
            library: downloadLibrary(allowSync: false),
            providerEndpoints: authorizedEndpoints
        ).isAuthorized)
    }

    @Test func librarySectionPreservesItsOwnAllowSyncFact() async throws {
        let session = makeDownloadAuthorizationMockSession { request in
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["X-Plex-Container-Total-Size": "1"]
            ))
            let data: Data
            if request.url?.path == "/library/sections/all" {
                data = Data(#"{"MediaContainer":{"Directory":[{"key":"1","title":"Movies","type":"movie","allowSync":true}]}}"#.utf8)
            } else {
                data = Data(#"{"MediaContainer":{"size":1,"totalSize":1,"Metadata":[{"ratingKey":"42","title":"Movie"}]}}"#.utf8)
            }
            return (response, data)
        }
        let configuration = PlexConnectionConfiguration(
            serverURL: try #require(URL(string: "https://plex.local:32400")),
            token: "server-token",
            clientContext: PlexClientContext(clientIdentifier: "tests")
        )

        let libraries = try await PlexAPIClient(session: session).fetchLibraries(
            using: configuration
        )

        #expect(libraries.first?.allowSync == true)
    }

    private func decodeUser(
        subscriptionType: String,
        state: String
    ) throws -> PlexAuthenticatedUser {
        try JSONDecoder().decode(
            PlexAuthenticatedUser.self,
            from: Data(#"""
            {
              "id": 42,
              "username": "test-user",
              "subscriptions": {
                "subscription": [{
                  "type": "\#(subscriptionType)",
                  "state": "\#(state)",
                  "mode": "recurring",
                  "active": true,
                  "subscribedAt": "2026-08-01T00:00:00Z"
                }]
              }
            }
            """#.utf8)
        )
    }

    private func providerEndpoints(
        allowSync: String?,
        includeDownloadFeature: Bool
    ) throws -> PlexLibraryProviderEndpoints {
        let allowSyncField = allowSync.map { "\"allowSync\":\($0)," } ?? ""
        let features = includeDownloadFeature
            ? #"[{"type":"subscribe","flavor":"download"}]"#
            : "[]"
        let data = Data("""
        {
          "MediaContainer": {
            \(allowSyncField)
            "MediaProvider": [{
              "identifier": "com.plexapp.plugins.library",
              "Feature": \(features)
            }]
          }
        }
        """.utf8)
        let envelope = try JSONDecoder().decode(PlexMediaProvidersEnvelope.self, from: data)
        return try envelope.mediaContainer.libraryProviderEndpoints()
    }
}

private func downloadLibrary(allowSync: Bool? = true) -> PlexLibrary {
    PlexLibrary(
        id: "1",
        title: "Movies",
        type: .movie,
        compositePath: nil,
        artPath: nil,
        thumbPath: nil,
        itemCount: 1,
        secondaryCount: nil,
        secondaryCountLabel: nil,
        updatedAt: nil,
        scannedAt: nil,
        contentChangedAt: nil,
        latestAddedAt: nil,
        latestItemTitle: nil,
        allowSync: allowSync
    )
}

private func makeDownloadAuthorizationMockSession(
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    DownloadAuthorizationURLProtocol.requestHandler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DownloadAuthorizationURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class DownloadAuthorizationURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler:
        (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
