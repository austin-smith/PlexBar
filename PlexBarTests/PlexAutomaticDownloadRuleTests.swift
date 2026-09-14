import PlexModels
import Foundation
import Testing
@testable import PlexBar

@Suite(.serialized)
struct PlexAutomaticDownloadRuleTests {
    @Test func registryPersistsExactRulesAndRemovesOnlyTheRequestedRule() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = PlexAutomaticDownloadRuleRegistry(rootURL: root)
        let first = rule(id: UUID(), title: "Alpha")
        let second = rule(id: UUID(), title: "Beta")

        try await registry.save(second)
        try await registry.save(first)
        #expect(try await registry.rules() == [first, second])

        let reloaded = PlexAutomaticDownloadRuleRegistry(rootURL: root)
        #expect(try await reloaded.rules() == [first, second])
        try await reloaded.remove(withID: first.id)
        #expect(try await reloaded.rules() == [second])
    }

    @Test func episodePolicyNeverSelectsMoviesOrClips() throws {
        let unwatchedEpisode = try item(type: "episode", watched: false)
        let watchedEpisode = try item(type: "episode", watched: true)
        let movie = try item(type: "movie", watched: false)
        let trailer = try item(type: "clip", watched: false, subtype: "trailer")

        #expect(PlexAutomaticDownloadPolicy.allEpisodes.includes(unwatchedEpisode))
        #expect(PlexAutomaticDownloadPolicy.allEpisodes.includes(watchedEpisode))
        #expect(PlexAutomaticDownloadPolicy.unwatchedEpisodes.includes(unwatchedEpisode))
        #expect(!PlexAutomaticDownloadPolicy.unwatchedEpisodes.includes(watchedEpisode))
        #expect(!PlexAutomaticDownloadPolicy.allEpisodes.includes(movie))
        #expect(!PlexAutomaticDownloadPolicy.allEpisodes.includes(trailer))
    }

    private func rule(id: UUID, title: String) -> PlexAutomaticDownloadRule {
        PlexAutomaticDownloadRule(
            id: id,
            accountID: 7,
            serverIdentifier: "server",
            libraryID: "2",
            sourceRatingKey: title,
            sourceChildrenPath: "/library/metadata/\(title)/children",
            sourceType: "show",
            title: title,
            posterPath: nil,
            policy: .unwatchedEpisodes,
            keepsUpToDate: true,
            removesWatchedDownloads: false,
            createdAt: Date(timeIntervalSince1970: title == "Alpha" ? 1 : 2),
            lastRefreshedAt: nil,
            lastErrorMessage: nil
        )
    }

    private func item(
        type: String,
        watched: Bool,
        subtype: String? = nil
    ) throws -> PlexMediaItem {
        let subtypeJSON = subtype.map { #", "subtype": "\#($0)""# } ?? ""
        return try JSONDecoder().decode(
            PlexMediaItem.self,
            from: Data(
                #"{"ratingKey":"1","title":"Item","type":"\#(type)","viewCount":\#(watched ? 1 : 0),"Media":[]\#(subtypeJSON)}"#.utf8
            )
        )
    }
}
