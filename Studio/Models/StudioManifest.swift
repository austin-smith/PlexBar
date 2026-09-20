import Foundation

struct StudioManifest: Codable, Sendable {
    var schemaVersion = 2
    var candidates: [StudioCandidate] = []
    var jobs: [StudioJob] = []
}
