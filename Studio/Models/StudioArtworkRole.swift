import Foundation

enum StudioArtworkRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case poster, backdrop, cover, avatar
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var ratio: Double {
        switch self { case .poster: 2.0 / 3; case .backdrop: 16.0 / 9; case .cover, .avatar: 1 }
    }
    var generationSize: String {
        switch self { case .poster: "1024x1536"; case .backdrop: "1536x864"; case .cover, .avatar: "1024x1024" }
    }
    var exportSize: CGSize {
        switch self {
        case .poster: CGSize(width: 600, height: 900)
        case .backdrop: CGSize(width: 1536, height: 864)
        case .cover: CGSize(width: 600, height: 600)
        case .avatar: CGSize(width: 360, height: 360)
        }
    }
}
