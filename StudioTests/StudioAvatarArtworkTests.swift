import Foundation
import PlexMockData
import Testing
@testable import PlexBarStudio

@Suite struct StudioAvatarArtworkTests {
    private func profile(in pack: StudioPack) throws -> PlexMockServerPayload.User {
        let value = try #require(pack.payload["users"]?.array?.first { $0["id"]?.integer == 18 })
        return try JSONDecoder().decode(PlexMockServerPayload.User.self, from: value.encoded())
    }

    @Test func newAvatarsUseReadableUsernamesAndExistingPathsStayStable() throws {
        let pack = try StudioFiles.loadPack(at: StudioFiles.repositoryContentURL)
        var user = try profile(in: pack)
        let existing = try #require(user.avatar)
        user.username = "A different username"
        #expect(try StudioAvatarArtwork.path(for: user, in: pack) == existing)
        user.avatar = nil
        #expect(try StudioAvatarArtwork.path(for: user, in: pack) == "/mock/avatars/a-different-username.png")
        user.username = "Amélie's / Browser"
        #expect(try StudioAvatarArtwork.path(for: user, in: pack) == "/mock/avatars/amelies-browser.png")
        user.username = "../"
        #expect(throws: (any Error).self) { try StudioAvatarArtwork.path(for: user, in: pack) }
    }

    @Test func newAvatarsCannotOverwriteRegisteredArtwork() throws {
        let pack = try StudioFiles.loadPack(at: StudioFiles.repositoryContentURL)
        var user = try profile(in: pack)
        user.avatar = nil
        user.username = "Dana Scully"
        #expect(throws: (any Error).self) { try StudioAvatarArtwork.path(for: user, in: pack) }
    }

    @Test func pickerShowsUserIdentityEvenWhenTheFilenameIsNumeric() throws {
        var pack = try StudioFiles.loadPack(at: StudioFiles.repositoryContentURL)
        var users = try #require(pack.payload["users"]?.array)
        let index = try #require(users.firstIndex { $0["id"]?.integer == 18 })
        let path = "/mock/avatars/user-18.png"
        users[index]["avatar"] = .string(path)
        pack.payload["users"] = .array(users)
        pack.payload["artwork"] = .array((pack.payload["artwork"]?.array ?? []) + [
            .object(["path": .string(path), "resource": .string("avatars/user-18.png")])
        ])
        #expect(try StudioAvatarArtwork.choices(in: pack).first { $0.path == path }?.title == "TheBaumer")
        users[index]["friendlyName"] = .string("Baumer")
        pack.payload["users"] = .array(users)
        #expect(try StudioAvatarArtwork.choices(in: pack).first { $0.path == path }?.title == "Baumer")
    }
}
