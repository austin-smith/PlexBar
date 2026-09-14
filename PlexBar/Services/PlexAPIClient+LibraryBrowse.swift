import PlexModels
import Foundation

extension PlexAPIClient {
    func fetchCollectionsPage(
        libraryID: String,
        using configuration: PlexConnectionConfiguration,
        start: Int = 0,
        size: Int = 100
    ) async throws -> PlexMediaPage {
        try await fetchMediaPage(
            contentPath: "/library/sections/\(libraryID)/collections",
            using: configuration,
            start: start,
            size: size
        )
    }

    func fetchPlaylistsPage(
        endpointPath: String,
        using configuration: PlexConnectionConfiguration,
        start: Int = 0,
        size: Int = 100
    ) async throws -> PlexMediaPage {
        try await fetchMediaPage(
            contentPath: endpointPath,
            using: configuration,
            start: start,
            size: size
        )
    }

    func fetchLibraryBrowseDefinition(
        sectionPath: String,
        contentPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> PlexLibraryBrowseDefinition {
        async let types = fetchLibraryBrowseTypes(
            sectionPath: sectionPath,
            using: configuration
        )
        async let filters = fetchLibraryFilters(
            sectionPath: sectionPath,
            using: configuration
        )
        async let sorts = fetchLibrarySorts(
            sectionPath: sectionPath,
            using: configuration
        )

        return try await PlexLibraryBrowseDefinition(
            contentPath: contentPath,
            filters: filters,
            sorts: sorts,
            types: types
        )
    }

    func fetchLibraryFilterValues(
        for definition: PlexLibraryFilterDefinition,
        using configuration: PlexConnectionConfiguration
    ) async throws -> [PlexLibraryFilterValue] {
        guard let valuesPath = definition.valuesPath else {
            throw PlexAPIError.invalidResponse
        }
        let data = try await fetchLibraryDescriptorData(
            path: valuesPath,
            using: configuration
        )

        do {
            return try JSONDecoder()
                .decode(PlexLibraryFilterValuesEnvelope.self, from: data)
                .mediaContainer
                .values(for: definition)
        } catch let error as PlexAPIError {
            throw error
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }
}

private extension PlexAPIClient {
    func fetchLibraryBrowseTypes(
        sectionPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> [PlexLibraryBrowseType] {
        guard var components = URLComponents(string: sectionPath) else {
            throw PlexAPIError.invalidServerURL
        }
        components.queryItems = (components.queryItems ?? [])
            + [URLQueryItem(name: "includeDetails", value: "1")]
        guard let path = components.string else {
            throw PlexAPIError.invalidServerURL
        }
        let data = try await fetchLibraryDescriptorData(path: path, using: configuration)
        do {
            return try JSONDecoder().decode(PlexLibraryBrowseEnvelope.self, from: data)
                .mediaContainer.types
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }

    func fetchLibraryFilters(
        sectionPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> [PlexLibraryFilterDefinition] {
        let data = try await fetchLibraryDescriptorData(
            sectionPath: sectionPath,
            descriptor: "filters",
            using: configuration
        )

        do {
            return try JSONDecoder()
                .decode(PlexLibraryFilterEnvelope.self, from: data)
                .mediaContainer
                .filters
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }

    func fetchLibrarySorts(
        sectionPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> [PlexLibrarySortDefinition] {
        let data = try await fetchLibraryDescriptorData(
            sectionPath: sectionPath,
            descriptor: "sorts",
            using: configuration
        )

        do {
            return try JSONDecoder()
                .decode(PlexLibrarySortEnvelope.self, from: data)
                .mediaContainer
                .sorts
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }

    func fetchLibraryDescriptorData(
        sectionPath: String,
        descriptor: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> Data {
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: sectionPath,
            appendingPathComponent: descriptor
        ) else {
            throw PlexAPIError.invalidServerURL
        }

        let request = PlexRequestBuilder(clientContext: configuration.clientContext).request(
            url: endpoint,
            accept: "application/json",
            token: configuration.token
        )
        return try await data(for: request)
    }

    func fetchLibraryDescriptorData(
        path: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> Data {
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: path
        ) else {
            throw PlexAPIError.invalidServerURL
        }

        let request = PlexRequestBuilder(clientContext: configuration.clientContext).request(
            url: endpoint,
            accept: "application/json",
            token: configuration.token
        )
        return try await data(for: request)
    }
}
