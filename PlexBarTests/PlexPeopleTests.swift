import Foundation
import Testing
@testable import PlexBar

@Suite(.serialized)
struct PlexPeopleTests {
    @Test func decodesPublishedPeopleFieldsAndSeparatesCrewFromOrderedCast() throws {
        let item = try JSONDecoder().decode(PlexMediaItem.self, from: Data(#"""
        {
          "ratingKey": "42",
          "title": "Movie",
          "type": "movie",
          "Director": [{
            "id": 10,
            "tag": "Director Person",
            "tagKey": "director-key",
            "tagType": 4,
            "filter": "director=10",
            "thumb": "https://metadata-static.plex.tv/director.jpg"
          }],
          "Writer": [
            { "id": 98, "tag": "Director Person", "tagKey": "director-key" },
            { "id": 11, "tag": "Writer Person" }
          ],
          "Producer": [{ "id": 12, "tag": "Producer Person" }],
          "Role": [
            { "id": 21, "tag": "Second Billing", "role": "Friend", "order": 2 },
            { "id": 20, "tag": "First Billing", "role": "Lead", "order": 1 },
            {
              "id": 99,
              "tag": "Director Person",
              "tagKey": "director-key",
              "role": "Alex",
              "order": 3
            }
          ]
        }
        """#.utf8))

        #expect(item.directors[0].id == 10)
        #expect(item.directors[0].tagKey == "director-key")
        #expect(item.directors[0].tagType == 4)
        #expect(item.directors[0].filter == "director=10")
        #expect(item.directors[0].thumb == "https://metadata-static.plex.tv/director.jpg")
        #expect(item.producers.map(\.tag) == ["Producer Person"])

        let presentation = PlexCastAndCrewPresentation(item: item)
        #expect(presentation.crew.map(\.name) == [
            "Director Person", "Writer Person", "Producer Person"
        ])
        #expect(presentation.crew.map(\.subtitle) == [
            "Director · Writer", "Writer", "Producer"
        ])
        #expect(presentation.cast.map(\.name) == [
            "First Billing", "Second Billing", "Director Person"
        ])
        #expect(presentation.cast.map(\.subtitle) == [
            "Lead", "Friend", "Alex"
        ])
        #expect(presentation.crew.compactMap(\.route).map(\.identifier) == [
            "director-key", "11", "12"
        ])
        #expect(presentation.cast.compactMap(\.route).map(\.identifier) == [
            "20", "21", "director-key"
        ])
        #expect(presentation.cast.compactMap(\.route).map(\.name) == [
            "First Billing", "Second Billing", "Director Person"
        ])
    }

    @Test func episodeWithoutRolesLoadsCastFromItsExactSeriesIdentity() async throws {
        let episode = try JSONDecoder().decode(PlexMediaItem.self, from: Data(#"""
        {
          "ratingKey": "episode-17",
          "type": "episode",
          "title": "Are We Really Doing This?",
          "grandparentRatingKey": "show-90",
          "Producer": [{ "id": 8, "tag": "Episode Producer" }]
        }
        """#.utf8))
        let capture = RequestCapture()
        let session = makePeopleMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data(#"""
            {
              "MediaContainer": {
                "Metadata": [{
                  "ratingKey": "show-90",
                  "type": "show",
                  "title": "90 Day Fiancé",
                  "Role": [
                    { "id": 22, "tag": "Series Lead", "role": "Self", "order": 1 },
                    { "id": 23, "tag": "Series Regular", "role": "Self", "order": 2 }
                  ]
                }]
              }
            }
            """#.utf8))
        }
        let configuration = PlexConnectionConfiguration(
            serverURL: try #require(URL(string: "https://plex.local:32400")),
            token: "server-token",
            clientContext: PlexClientContext(clientIdentifier: "test-client")
        )

        let cast = try await PlexAPIClient(session: session).fetchEpisodeSeriesCast(
            for: episode,
            using: configuration
        )
        let presentation = PlexCastAndCrewPresentation(
            item: episode,
            episodeSeriesCast: cast
        )

        #expect(capture.requests.count == 1)
        #expect(capture.request?.url?.path == "/library/metadata/show-90")
        #expect(capture.request?.url?.query == "includeOptionalElements=Image,Marker,Rating&includeGuids=1")
        #expect(capture.request?.value(forHTTPHeaderField: "X-Plex-Token") == "server-token")
        #expect(presentation.cast.map(\.name) == ["Series Lead", "Series Regular"])
        #expect(presentation.crew.map(\.name) == ["Episode Producer"])
    }

    @Test func aPersonsDestinationDoesNotDependOnTheOriginatingCredit() throws {
        let lead = try JSONDecoder().decode(PlexMediaItem.self, from: Data(#"""
        {
          "ratingKey": "1",
          "title": "First Movie",
          "type": "movie",
          "Role": [{ "id": 20, "tag": "Same Person", "role": "Lead" }]
        }
        """#.utf8))
        let guest = try JSONDecoder().decode(PlexMediaItem.self, from: Data(#"""
        {
          "ratingKey": "2",
          "title": "Second Movie",
          "type": "movie",
          "Role": [{ "id": 20, "tag": "Same Person", "role": "Guest" }]
        }
        """#.utf8))

        let leadCredit = try #require(PlexCastAndCrewPresentation(item: lead).cast.first)
        let guestCredit = try #require(PlexCastAndCrewPresentation(item: guest).cast.first)

        #expect(leadCredit.subtitle == "Lead")
        #expect(guestCredit.subtitle == "Guest")
        #expect(leadCredit.route == guestCredit.route)
    }

    @Test func directEpisodeCastWinsWithoutRequestingSeriesMetadata() async throws {
        let episode = try JSONDecoder().decode(PlexMediaItem.self, from: Data(#"""
        {
          "ratingKey": "episode-17",
          "type": "episode",
          "title": "Episode",
          "grandparentRatingKey": "show-90",
          "Role": [{ "id": 31, "tag": "Guest Star", "role": "Guest" }]
        }
        """#.utf8))
        let session = makePeopleMockSession { _ in
            Issue.record("Series metadata must not be requested when the episode has direct cast.")
            throw PlexAPIError.invalidResponse
        }
        let configuration = PlexConnectionConfiguration(
            serverURL: try #require(URL(string: "https://plex.local:32400")),
            token: "server-token",
            clientContext: PlexClientContext(clientIdentifier: "test-client")
        )

        let inherited = try await PlexAPIClient(session: session).fetchEpisodeSeriesCast(
            for: episode,
            using: configuration
        )
        let presentation = PlexCastAndCrewPresentation(
            item: episode,
            episodeSeriesCast: [
                PlexTag(
                    id: 99,
                    tag: "Wrong Series Cast",
                    tagKey: nil,
                    tagType: nil,
                    filter: nil,
                    role: "Self",
                    thumb: nil,
                    order: nil
                ),
            ]
        )

        #expect(inherited.isEmpty)
        #expect(presentation.cast.map(\.name) == ["Guest Star"])
    }

    @Test func personEndpointsUseExactAuthenticatedPMSPaths() async throws {
        let capture = RequestCapture()
        let session = makePeopleMockSession { request in
            capture.record(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            if request.url?.path.hasSuffix("/media") == true {
                return (response, Data(#"{"MediaContainer":{"Metadata":[{"ratingKey":"50","title":"Film"}]}}"#.utf8))
            }
            return (response, Data(#"{"MediaContainer":{"Directory":[{"id":53374,"tag":"Jay Chandrasekhar","tagKey":"person-key"}]}}"#.utf8))
        }
        let configuration = PlexConnectionConfiguration(
            serverURL: try #require(URL(string: "https://plex.local:32400")),
            token: "server-token",
            clientContext: PlexClientContext(clientIdentifier: "test-client")
        )
        let client = PlexAPIClient(session: session)

        let person = try await client.fetchPerson(identifier: "person-key", using: configuration)
        let media = try await client.fetchPersonMedia(identifier: "person-key", using: configuration)

        #expect(person.id == 53374)
        #expect(media.map(\.title) == ["Film"])
        #expect(capture.requests.map { $0.url?.path } == [
            "/library/people/person-key",
            "/library/people/person-key/media",
        ])
        #expect(capture.requests.allSatisfy {
            $0.value(forHTTPHeaderField: "X-Plex-Token") == "server-token"
        })
    }

    @Test func portraitRequestsNeverSendServerTokensToExternalHosts() throws {
        let serverURL = try #require(URL(string: "https://plex.local:32400"))

        let local = try #require(PlexImageRequest(
            path: "/library/metadata/10/thumb",
            serverURL: serverURL,
            serverToken: "secret"
        ))
        #expect(local.url.absoluteString == "https://plex.local:32400/library/metadata/10/thumb")
        #expect(local.token == "secret")

        let external = try #require(PlexImageRequest(
            path: "https://metadata-static.plex.tv/person.jpg",
            serverURL: serverURL,
            serverToken: "secret"
        ))
        #expect(external.url.absoluteString == "https://metadata-static.plex.tv/person.jpg")
        #expect(external.token.isEmpty)
    }

    @Test @MainActor func avatarRequestsScopeCredentialsToTrustedOrigins() throws {
        let serverURL = try #require(URL(string: "https://plex.local:32400"))

        let serverAvatar = try #require(PlexAvatarView.resolveRequest(
            thumb: "https://plex.local:32400/accounts/7/avatar",
            serverURL: serverURL,
            serverToken: "server-secret",
            userToken: "user-secret"
        ))
        #expect(serverAvatar.token == "server-secret")

        let plexAvatar = try #require(PlexAvatarView.resolveRequest(
            thumb: "https://plex.tv/users/7/avatar",
            serverURL: serverURL,
            serverToken: "server-secret",
            userToken: "user-secret"
        ))
        #expect(plexAvatar.token == "user-secret")

        let externalAvatar = try #require(PlexAvatarView.resolveRequest(
            thumb: "https://example.com/users/7/avatar",
            serverURL: serverURL,
            serverToken: "server-secret",
            userToken: "user-secret"
        ))
        #expect(externalAvatar.token.isEmpty)
    }
}

private func makePeopleMockSession(
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    PeopleMockURLProtocol.requestHandler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PeopleMockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class PeopleMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
