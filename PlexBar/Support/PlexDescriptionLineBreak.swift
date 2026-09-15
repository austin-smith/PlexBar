import AppKit
import CoreText

/// Finds the first natural line break without reserving space for the button.
/// This is a read-only text calculation; it has no views or layout callbacks.
struct PlexDescriptionLineBreak {
    let firstLine: String
    let remainingText: String

    init?(summary: String, width: CGFloat, font: NSFont) {
        guard width > 0, width.isFinite, !summary.isEmpty else { return nil }
        let text = summary as NSString
        let attributed = NSAttributedString(string: summary, attributes: [.font: font])
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let firstLength = CTTypesetterSuggestLineBreak(typesetter, 0, width)
        guard firstLength > 0, firstLength < text.length else { return nil }
        let secondLength = CTTypesetterSuggestLineBreak(typesetter, firstLength, width)
        guard firstLength + secondLength < text.length else { return nil }

        firstLine = text.substring(to: firstLength).trimmingCharacters(in: .newlines)
        remainingText = text.substring(from: firstLength)
    }
}
