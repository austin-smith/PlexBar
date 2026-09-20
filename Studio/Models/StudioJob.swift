import Foundation

struct StudioJob: Codable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let kind: Kind
    let prompt: String
    let createdAt: Date
    var threadID: String?
    var model: String?
    var status: Status = .queued
    var executable: String?
    var message: String?
    var draft: StudioTitleDraft?
    var artwork: Artwork?
    enum Kind: String, Codable { case artwork, catalog }
    enum Status: String, Codable { case queued, running, review, accepted, rejected, failed, interrupted }
    var directory: String { "jobs/\(id.uuidString)" }
    struct Destination: Codable, Equatable, Sendable {
        var path: String
        var hash: String?
        var acceptedCandidateID: UUID?
    }
    struct Artwork: Codable, Sendable {
        var sourceCandidateID: UUID?
        var recordID: String?
        var userID: Int?
        var userAvatarPath: String?
        var assetPath: String
        var role: StudioArtworkRole
        var references: [String]
        var referenceHashes: [String]
        var destination: Destination?
    }
}
