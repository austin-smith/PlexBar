import Foundation

struct StudioArtworkInstructions: Codable, Equatable, Sendable {
    var avatar: String
    var referenceArtwork: String

    enum Section: String, CaseIterable, Identifiable {
        case referenceArtwork, avatar
        var id: String { rawValue }
        var title: String { self == .avatar ? "Avatar" : "Reference Artwork" }
        var keyPath: WritableKeyPath<StudioArtworkInstructions, String> {
            self == .avatar ? \.avatar : \.referenceArtwork
        }
    }

    func validate() throws {
        for section in Section.allCases where self[keyPath: section.keyPath].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw StudioError.invalid("\(section.title) instructions cannot be empty.")
        }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    func prompt(item: StudioGalleryItem, role: StudioArtworkRole, artDirection: String, revising: Bool) throws -> String {
        try validate()
        var sections = [
            "Subject: \(item.title)\n\(item.subtitle)",
            role == .avatar ? avatar : referenceArtwork,
            "Reference image: Image 1."
        ]
        if revising { sections.append("Image 2 is the previous candidate.") }
        if !artDirection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("\(revising ? "Requested revision" : "Additional instructions"):\n\(artDirection)")
        }
        sections.append("Generate exactly one image at \(role.generationSize). Save it in the supplied job directory and return it through the image-generation tool.")
        return sections.joined(separator: "\n\n")
    }
}
