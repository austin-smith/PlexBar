import AppKit
import CoreText
import Testing
@testable import PlexBar

@MainActor
struct PlexDescriptionLineBreakTests {
    private let summary = "A successful real estate agent living in the shadow of his wealthier older brother has his carefully ordered life upended when the eccentric young man he once mentored through a Big Brother program unexpectedly returns, convinced they're family and refusing to leave."

    @Test(arguments: [180.0, 260.0, 560.0], [13.0, 20.0])
    func firstLineUsesFullWidthWithoutDroppingText(width: Double, size: Double) throws {
        let font = NSFont.systemFont(ofSize: size)
        let result = try #require(PlexDescriptionLineBreak(summary: summary, width: width, font: font))
        #expect(result.firstLine + result.remainingText == summary)
        #expect(renderedWidth(result.firstLine, font: font) <= width)
        let nextWord = try #require(result.remainingText.split(separator: " ").first)
        #expect(renderedWidth(result.firstLine + nextWord, font: font) > width)
    }

    @Test(arguments: ["", "A short description.", "First line.\nSecond line."])
    func fittingTextNeedsNoMoreButton(text: String) {
        #expect(PlexDescriptionLineBreak(summary: text, width: 300, font: .systemFont(ofSize: 13)) == nil)
    }

    @Test func resizingChangesTruncationWithoutRetainingPreviousLayout() {
        let font = NSFont.systemFont(ofSize: 13)
        #expect(PlexDescriptionLineBreak(summary: summary, width: 260, font: font) != nil)
        #expect(PlexDescriptionLineBreak(summary: summary, width: 1_200, font: font) == nil)
        #expect(PlexDescriptionLineBreak(summary: summary, width: 260, font: font) != nil)
    }

    @Test func unicodeIsPreservedAcrossTheLineBreak() throws {
        let text = String(repeating: "Café 👩🏽‍🚀 déjà vu — family stories continue. ", count: 8)
        let result = try #require(PlexDescriptionLineBreak(summary: text, width: 260, font: .systemFont(ofSize: 13)))
        #expect(result.firstLine + result.remainingText == text)
    }

    private func renderedWidth(_ text: String, font: NSFont) -> Double {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        return CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line)
    }
}
