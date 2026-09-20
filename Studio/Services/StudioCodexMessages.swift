import Foundation

struct StudioCodexApproval: Identifiable {
    let id: UUID = UUID()
    let rpcID: StudioJSON
    let method: String
    let details: String
}

struct StudioCodexResult: Sendable {
    var threadID: String
    var model: String
    var text: String
    var images: [StudioJSON]
}
