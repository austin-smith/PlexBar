import Foundation

#if DEBUG
import PlexMockData

enum PlexMockServerPayloadError: Error {
    case missingResource
}

enum PlexMockServerResourceLocator {
    static func url(for relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Resources/MockServer/\(relativePath)")
    }
}

extension PlexMockServerPayload {
    static func loadDefault() throws -> PlexMockServerPayload {
        let url = PlexMockServerResourceLocator.url(for: "mock-server.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PlexMockServerPayloadError.missingResource
        }

        let data = try Data(contentsOf: url)
        let payload = try JSONDecoder().decode(PlexMockServerPayload.self, from: data)
        try payload.validateProfiles()
        return payload
    }
}

extension PlexMockMediaCatalog {
    static func loadDefault() throws -> Self {
        try Self(data: Data(contentsOf: PlexMockServerResourceLocator.url(for: "media-catalog.json")))
    }
}
#endif
