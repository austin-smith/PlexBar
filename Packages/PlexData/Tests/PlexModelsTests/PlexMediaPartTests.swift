import Foundation
import Testing
@testable import PlexModels

struct PlexMediaPartTests {
    @Test func decodesPreviewIndexAvailabilityAndNumericStrings() throws {
        let part = try JSONDecoder().decode(PlexMediaPart.self, from: Data(#"{"id":"12","duration":"2500","indexes":"sd"}"#.utf8))
        #expect(part.id == 12)
        #expect(part.duration == 2_500)
        #expect(part.indexes == "sd")
        let absent = try JSONDecoder().decode(PlexMediaPart.self, from: Data(#"{"id":13}"#.utf8))
        #expect(absent.indexes == nil)
    }
}
