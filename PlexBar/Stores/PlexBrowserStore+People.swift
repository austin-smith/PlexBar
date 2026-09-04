import Foundation

struct PlexPeopleState {
    var peopleByIdentifier: [String: PlexTag] = [:]
    var mediaByIdentifier: [String: [PlexMediaItem]] = [:]
    var loadedIdentifiers: Set<String> = []
    var loadingIdentifiers: Set<String> = []
    var errorMessagesByIdentifier: [String: String] = [:]
    var recency: [String] = []
}

extension PlexBrowserStore {
    func episodeSeriesCast(for item: PlexMediaItem) async -> [PlexTag] {
        do {
            return try await connectionStore.perform { configuration in
                try await self.client.fetchEpisodeSeriesCast(
                    for: item,
                    using: configuration
                )
            }
        } catch {
            return []
        }
    }

    func person(for route: PlexPersonRoute) -> PlexTag? {
        peopleState.peopleByIdentifier[route.identifier]
    }

    func personMedia(for route: PlexPersonRoute) -> [PlexMediaItem] {
        peopleState.mediaByIdentifier[route.identifier] ?? []
    }

    func isLoadingPerson(_ route: PlexPersonRoute) -> Bool {
        peopleState.loadingIdentifiers.contains(route.identifier)
    }

    func personErrorMessage(for route: PlexPersonRoute) -> String? {
        peopleState.errorMessagesByIdentifier[route.identifier]
    }

    func resetPeople() {
        peopleGenerationsByIdentifier.removeAll()
        peopleState = PlexPeopleState()
    }

    func loadPerson(
        _ route: PlexPersonRoute,
        forceRefresh: Bool = false
    ) async {
        guard connectionStore.settings.hasValidConfiguration else {
            resetPeople()
            return
        }
        guard !peopleState.loadingIdentifiers.contains(route.identifier) else {
            return
        }
        if peopleState.loadedIdentifiers.contains(route.identifier), !forceRefresh {
            recordPeopleAccess(route.identifier)
            return
        }

        let generation = peopleGeneration(for: route.identifier)
        peopleState.loadingIdentifiers.insert(route.identifier)
        defer {
            if peopleGenerationsByIdentifier[route.identifier] == generation {
                peopleState.loadingIdentifiers.remove(route.identifier)
            }
        }

        do {
            let result = try await connectionStore.perform { configuration in
                async let person = self.client.fetchPerson(
                    identifier: route.identifier,
                    using: configuration
                )
                async let media = self.client.fetchPersonMedia(
                    identifier: route.identifier,
                    using: configuration
                )
                return try await (person, media)
            }
            guard peopleGenerationsByIdentifier[route.identifier] == generation else {
                return
            }
            peopleState.peopleByIdentifier[route.identifier] = result.0
            peopleState.mediaByIdentifier[route.identifier] = result.1
            peopleState.loadedIdentifiers.insert(route.identifier)
            peopleState.errorMessagesByIdentifier[route.identifier] = nil
            recordPeopleAccess(route.identifier)
        } catch {
            guard peopleGenerationsByIdentifier[route.identifier] == generation,
                  !Task.isCancelled else {
                return
            }
            peopleState.errorMessagesByIdentifier[route.identifier] = error.localizedDescription
            recordPeopleAccess(route.identifier)
        }
    }
}

private extension PlexBrowserStore {
    func peopleGeneration(for identifier: String) -> UUID {
        if let generation = peopleGenerationsByIdentifier[identifier] {
            return generation
        }
        let generation = UUID()
        peopleGenerationsByIdentifier[identifier] = generation
        return generation
    }

    func recordPeopleAccess(_ identifier: String) {
        peopleState.recency.removeAll { $0 == identifier }
        peopleState.recency.append(identifier)

        while peopleState.recency.count > peopleLimit {
            let evictedIdentifier = peopleState.recency.removeFirst()
            peopleState.peopleByIdentifier[evictedIdentifier] = nil
            peopleState.mediaByIdentifier[evictedIdentifier] = nil
            peopleState.loadedIdentifiers.remove(evictedIdentifier)
            peopleState.loadingIdentifiers.remove(evictedIdentifier)
            peopleState.errorMessagesByIdentifier[evictedIdentifier] = nil
            peopleGenerationsByIdentifier[evictedIdentifier] = nil
        }
    }
}
