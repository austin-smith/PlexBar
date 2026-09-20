import Foundation

struct StudioCandidate: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var recordID: String?
    var userID: Int?
    var assetPath: String
    var role: StudioArtworkRole
    var file: String
    var prompt: String
    var revisedPrompt: String?
    var model: String
    var jobID: UUID
    var referenceHashes: [String]
    var outputHash: String
    var createdAt: Date
    var decidedAt: Date?
    var decision: Decision
    enum Decision: String, Codable, Sendable { case pending, accepted, rejected }
}
