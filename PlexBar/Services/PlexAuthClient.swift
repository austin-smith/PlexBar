import Foundation

protocol PlexAccountJWTClient: Sendable {
    func registerJWK(
        _ jwk: PlexJSONWebKey,
        legacyToken: String,
        clientContext: PlexClientContext
    ) async throws
    func fetchJWTNonce(clientContext: PlexClientContext) async throws -> String
    func exchangeDeviceJWT(_ deviceJWT: String, clientContext: PlexClientContext) async throws -> String
}

struct PlexAuthClient: PlexAccountJWTClient, Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchAuthenticatedUser(
        userToken: String,
        clientContext: PlexClientContext
    ) async throws -> PlexAuthenticatedUser {
        let request = PlexRequestBuilder(clientContext: clientContext).request(
            url: PlexRemoteService.apiURL(path: "/api/v2/user"),
            accept: "application/json",
            token: userToken
        )

        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try JSONDecoder().decode(PlexAuthenticatedUser.self, from: data)
    }

    func createPin(
        jwk: PlexJSONWebKey,
        strong: Bool = true,
        clientContext: PlexClientContext
    ) async throws -> PlexPin {
        var request = PlexRequestBuilder(clientContext: clientContext).request(
            url: PlexRemoteService.clientsURL(path: "/api/v2/pins"),
            method: "POST",
            accept: "application/json"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PlexPinRequest(jwk: jwk, strong: strong))

        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try JSONDecoder().decode(PlexPin.self, from: data)
    }

    func fetchPin(
        id: String,
        deviceJWT: String,
        clientContext: PlexClientContext
    ) async throws -> PlexPin {
        let request = PlexRequestBuilder(clientContext: clientContext).request(
            url: PlexRemoteService.clientsURL(
                path: "/api/v2/pins/\(id)",
                queryItems: [URLQueryItem(name: "deviceJWT", value: deviceJWT)]
            ),
            accept: "application/json"
        )

        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try JSONDecoder().decode(PlexPin.self, from: data)
    }

    func registerJWK(
        _ jwk: PlexJSONWebKey,
        legacyToken: String,
        clientContext: PlexClientContext
    ) async throws {
        var request = PlexRequestBuilder(clientContext: clientContext).request(
            url: PlexRemoteService.clientsURL(path: "/api/v2/auth/jwk"),
            method: "POST",
            accept: "application/json",
            token: legacyToken
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PlexJWKRegistrationRequest(jwk: jwk))
        let (_, response) = try await session.data(for: request)
        try validate(response: response)
    }

    func fetchJWTNonce(clientContext: PlexClientContext) async throws -> String {
        let request = PlexRequestBuilder(clientContext: clientContext).request(
            url: PlexRemoteService.clientsURL(path: "/api/v2/auth/nonce"),
            accept: "application/json"
        )
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try JSONDecoder().decode(PlexJWTNonceResponse.self, from: data).nonce
    }

    func exchangeDeviceJWT(
        _ deviceJWT: String,
        clientContext: PlexClientContext
    ) async throws -> String {
        var request = PlexRequestBuilder(clientContext: clientContext).request(
            url: PlexRemoteService.clientsURL(path: "/api/v2/auth/token"),
            method: "POST",
            accept: "application/json"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PlexJWTExchangeRequest(jwt: deviceJWT))
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try JSONDecoder().decode(PlexJWTExchangeResponse.self, from: data).authToken
    }

    func fetchServers(userToken: String, clientContext: PlexClientContext) async throws -> [PlexServerResource] {
        let requestBuilder = PlexRequestBuilder(clientContext: clientContext)
        let resourcesRequest = requestBuilder.request(
            url: PlexRemoteService.clientsURL(
                path: "/api/v2/resources",
                queryItems: [
                    URLQueryItem(name: "includeHttps", value: "1"),
                    URLQueryItem(name: "includeRelay", value: "1"),
                    URLQueryItem(name: "includeIPv6", value: "1")
                ]
            ),
            accept: "application/json",
            token: userToken
        )
        let devicesRequest = requestBuilder.request(
            url: PlexRemoteService.clientsURL(path: "/api/v2/devices"),
            accept: "application/json",
            token: userToken
        )

        let (resourcesData, resourcesResponse) = try await session.data(for: resourcesRequest)
        try validate(response: resourcesResponse)
        let (devicesData, devicesResponse) = try await session.data(for: devicesRequest)
        try validate(response: devicesResponse)

        let decoder = JSONDecoder()
        let resourceResponses = try decoder.decode([PlexServerResourceResponse].self, from: resourcesData)
        let deviceResponses = try decoder.decode([PlexServerDeviceResponse].self, from: devicesData)
        let tokensByServerID = deviceResponses.reduce(into: [String: String]()) { result, device in
            guard let credential = device.serverCredential else {
                return
            }
            result[credential.serverID] = credential.token
        }

        return resourceResponses.compactMap { resource in
            guard let identifier = resource.clientIdentifier?.nilIfBlank,
                  let token = tokensByServerID[identifier] else {
                return nil
            }
            return resource.serverResource(accessToken: token)
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

extension PlexAuthError {
    var requiresTokenRefresh: Bool {
        guard case .badStatusCode(let statusCode) = self else {
            return false
        }
        return statusCode == 401 || statusCode == 498
    }
}

private struct PlexServerResourceResponse: Decodable {
    let name: String?
    let clientIdentifier: String?
    let provides: String?
    let productVersion: String?
    let connections: [PlexServerConnectionResponse]?

    func serverResource(accessToken: String) -> PlexServerResource? {
        let provides = provides ?? ""
        guard provides.split(separator: ",").contains(where: { $0 == "server" }) else {
            return nil
        }

        guard let identifier = clientIdentifier?.nilIfBlank,
              let name = name?.nilIfBlank else {
            return nil
        }

        let connections = (connections ?? []).compactMap(\.serverConnection)
        guard !connections.isEmpty else {
            return nil
        }

        return PlexServerResource(
            id: identifier,
            name: name,
            productVersion: productVersion?.nilIfBlank,
            accessToken: accessToken,
            connections: connections
        )
    }
}

private struct PlexServerDeviceResponse: Decodable {
    let clientIdentifier: String?
    let provides: String?
    let token: String?

    var serverCredential: (serverID: String, token: String)? {
        let provides = provides ?? ""
        guard provides.split(separator: ",").contains(where: { $0 == "server" }),
              let serverID = clientIdentifier?.nilIfBlank,
              let token = token?.nilIfBlank else {
            return nil
        }
        return (serverID, token)
    }
}

private struct PlexServerConnectionResponse: Decodable {
    let uri: String?
    let local: Bool?
    let relay: Bool?

    var serverConnection: PlexServerConnection? {
        guard let uri = uri?.nilIfBlank.flatMap(URL.init(string:)) else {
            return nil
        }

        return PlexServerConnection(
            uri: uri,
            local: local ?? false,
            relay: relay ?? false
        )
    }
}

struct PlexPin: Decodable {
    let id: Int
    let code: String
    let authToken: String?
}

private struct PlexPinRequest: Encodable {
    let jwk: PlexJSONWebKey
    let strong: Bool
}

private struct PlexJWKRegistrationRequest: Encodable {
    let jwk: PlexJSONWebKey
}

private struct PlexJWTNonceResponse: Decodable {
    let nonce: String
}

private struct PlexJWTExchangeRequest: Encodable {
    let jwt: String
}

private struct PlexJWTExchangeResponse: Decodable {
    let authToken: String

    private enum CodingKeys: String, CodingKey {
        case authToken = "auth_token"
    }
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
