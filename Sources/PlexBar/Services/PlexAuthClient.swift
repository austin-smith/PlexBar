import Foundation

struct PlexAuthClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchAuthenticatedUser(userToken: String, clientContext: PlexClientContext) async throws -> PlexAuthenticatedUser {
        let request = PlexRequestBuilder(clientContext: clientContext).request(
            url: PlexRemoteService.apiURL(path: "/api/v2/user"),
            accept: "application/json",
            token: userToken
        )

        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try JSONDecoder().decode(PlexAuthenticatedUser.self, from: data)
    }

    func createPin(clientContext: PlexClientContext) async throws -> PlexPin {
        let request = PlexRequestBuilder(clientContext: clientContext).request(
            url: PlexRemoteService.apiURL(
                path: "/api/v2/pins",
                queryItems: [URLQueryItem(name: "strong", value: "true")]
            ),
            method: "POST",
            accept: "application/json"
        )

        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try JSONDecoder().decode(PlexPin.self, from: data)
    }

    func fetchPin(id: String, clientContext: PlexClientContext) async throws -> PlexPin {
        let request = PlexRequestBuilder(clientContext: clientContext).request(
            url: PlexRemoteService.apiURL(path: "/api/v2/pins/\(id)"),
            accept: "application/json"
        )

        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try JSONDecoder().decode(PlexPin.self, from: data)
    }

    func fetchServers(userToken: String, clientContext: PlexClientContext) async throws -> [PlexServerResource] {
        let request = PlexRequestBuilder(clientContext: clientContext).request(
            url: PlexRemoteService.apiURL(
                path: "/api/resources",
                queryItems: [
                    URLQueryItem(name: "includeHttps", value: "1"),
                    URLQueryItem(name: "includeRelay", value: "1"),
                    URLQueryItem(name: "includeIPv6", value: "1"),
                ]
            ),
            accept: "application/xml",
            token: userToken
        )

        let (data, response) = try await session.data(for: request)
        try validate(response: response)

        let document = try XMLDocument(data: data, options: [])
        let devices = try document.nodes(forXPath: "//Device")

        return devices.compactMap { node -> PlexServerResource? in
            guard let element = node as? XMLElement else {
                return nil
            }

            let provides = element.attribute(forName: "provides")?.stringValue ?? ""
            guard provides.split(separator: ",").contains(where: { $0 == "server" }) else {
                return nil
            }

            guard let identifier = element.attribute(forName: "clientIdentifier")?.stringValue?.nilIfBlank,
                  let name = element.attribute(forName: "name")?.stringValue?.nilIfBlank,
                  let accessToken = element.attribute(forName: "accessToken")?.stringValue?.nilIfBlank else {
                return nil
            }

            let productVersion = element.attribute(forName: "productVersion")?.stringValue?.nilIfBlank

            let connections = (element.elements(forName: "Connection")).compactMap { connection -> PlexServerConnection? in
                guard let uriString = connection.attribute(forName: "uri")?.stringValue,
                      let uri = URL(string: uriString) else {
                    return nil
                }

                return PlexServerConnection(
                    uri: uri,
                    local: connection.attribute(forName: "local")?.stringValue == "1",
                    relay: connection.attribute(forName: "relay")?.stringValue == "1"
                )
            }

            guard !connections.isEmpty else {
                return nil
            }

            return PlexServerResource(
                id: identifier,
                name: name,
                productVersion: productVersion,
                accessToken: accessToken,
                connections: connections
            )
        }
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAuthError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PlexAuthError.badStatusCode(httpResponse.statusCode)
        }
    }
}

struct PlexPin: Decodable {
    let id: Int
    let code: String
    let authToken: String?
}

enum PlexAuthError: LocalizedError {
    case invalidAuthURL
    case invalidResponse
    case badStatusCode(Int)
    case noServersFound

    var errorDescription: String? {
        switch self {
        case .invalidAuthURL:
            return "PlexBar could not build the Plex sign-in URL."
        case .invalidResponse:
            return "Plex.tv returned a response PlexBar could not read."
        case .badStatusCode(let statusCode):
            return "Plex.tv returned HTTP \(statusCode)."
        case .noServersFound:
            return "No Plex Media Servers were found for this account."
        }
    }
}
