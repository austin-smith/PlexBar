import Foundation

struct StudioAsset: Identifiable, Equatable, Sendable {
    let path: String
    let resource: String
    var id: String { path }
    var role: StudioArtworkRole {
        if path.contains("/avatars/") { return .avatar }
        if resource.contains("backdrop") { return .backdrop }
        if resource.contains("cover") { return .cover }
        return .poster
    }
}
