import Foundation

struct PlexGeoIPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchGeoLocation(
        ipAddress: String,
        userToken: String,
        clientContext: PlexClientContext
    ) async throws -> PlexGeoLocation? {
        let request = PlexRequestBuilder(clientContext: clientContext).request(
            url: PlexRemoteService.apiURL(
                path: "/api/v2/geoip",
                queryItems: [URLQueryItem(name: "ip_address", value: ipAddress)]
            ),
            accept: "application/xml",
            token: userToken
        )

        let (data, response) = try await session.data(for: request)
        try validate(response: response)

        let document = try XMLDocument(data: data, options: [])
        guard let locationElement = try document.nodes(forXPath: "//location").first as? XMLElement else {
            return nil
        }

        let geoLocation = PlexGeoLocation(
            city: locationElement.attribute(forName: "city")?.stringValue?.nilIfBlank,
            region: locationElement.attribute(forName: "subdivisions")?.stringValue?.nilIfBlank,
            country: locationElement.attribute(forName: "country")?.stringValue?.nilIfBlank,
            countryCode: locationElement.attribute(forName: "code")?.stringValue?.nilIfBlank
        )

        return geoLocation.displayName == nil ? nil : geoLocation
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexGeoIPError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PlexGeoIPError.badStatusCode(httpResponse.statusCode)
        }
    }
}

struct PlexGeoLocation: Equatable {
    let city: String?
    let region: String?
    let country: String?
    let countryCode: String?

    var displayName: String? {
        if let city, let region {
            return "\(city), \(region)"
        }

        if let city, let country {
            return "\(city), \(country)"
        }

        if let region, let country {
            return "\(region), \(country)"
        }

        return city ?? region ?? country
    }
}

enum PlexGeoIPError: LocalizedError {
    case invalidResponse
    case badStatusCode(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Plex.tv returned a GeoIP response PlexBar could not read."
        case .badStatusCode(let statusCode):
            return "Plex.tv returned HTTP \(statusCode) for GeoIP lookup."
        }
    }
}
