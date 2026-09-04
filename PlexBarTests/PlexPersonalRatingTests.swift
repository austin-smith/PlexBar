import Testing
@testable import PlexBar

struct PlexPersonalRatingTests {
    @Test func serverValuesMapToFiveStarsWithoutLosingHalfSteps() {
        #expect(PlexPersonalRating.stars(fromServerValue: nil) == nil)
        #expect(PlexPersonalRating.stars(fromServerValue: 0) == nil)
        #expect(PlexPersonalRating.stars(fromServerValue: 1) == 0.5)
        #expect(PlexPersonalRating.stars(fromServerValue: 2) == 1)
        #expect(PlexPersonalRating.stars(fromServerValue: 7) == 3.5)
        #expect(PlexPersonalRating.stars(fromServerValue: 10) == 5)
    }

    @Test func fiveStarValuesMapBackToThePlexServerScale() {
        #expect(PlexPersonalRating.serverValue(fromStars: 0.5) == 1)
        #expect(PlexPersonalRating.serverValue(fromStars: 1) == 2)
        #expect(PlexPersonalRating.serverValue(fromStars: 3.5) == 7)
        #expect(PlexPersonalRating.serverValue(fromStars: 5) == 10)
        #expect(PlexPersonalRating.serverValue(fromStars: 0) == nil)
        #expect(PlexPersonalRating.serverValue(fromStars: 5.5) == nil)
    }

    @Test func pointerPositionsSelectHalfStarStepsAcrossFiveVisibleStars() {
        #expect(PlexPersonalRating.stars(at: 0, controlWidth: 100) == 0.5)
        #expect(PlexPersonalRating.stars(at: 10, controlWidth: 100) == 0.5)
        #expect(PlexPersonalRating.stars(at: 10.1, controlWidth: 100) == 1)
        #expect(PlexPersonalRating.stars(at: 50, controlWidth: 100) == 2.5)
        #expect(PlexPersonalRating.stars(at: 70, controlWidth: 100) == 3.5)
        #expect(PlexPersonalRating.stars(at: 100, controlWidth: 100) == 5)
    }

    @Test func keyboardAndAccessibilityAdjustInHalfStarSteps() {
        #expect(PlexPersonalRating.adjustedServerValue(from: nil, by: 1) == 1)
        #expect(PlexPersonalRating.adjustedServerValue(from: 7, by: 1) == 8)
        #expect(PlexPersonalRating.adjustedServerValue(from: 7, by: -1) == 6)
        #expect(PlexPersonalRating.adjustedServerValue(from: 10, by: 1) == 10)
        #expect(PlexPersonalRating.adjustedServerValue(from: 1, by: -1) == nil)
    }

    @Test func labelsUseTheFiveStarPresentationScale() {
        #expect(PlexPersonalRating.title(forServerValue: nil) == "Rate")
        #expect(PlexPersonalRating.title(forServerValue: 2) == "1 Star")
        #expect(PlexPersonalRating.title(forServerValue: 7) == "3.5 Stars")
        #expect(PlexPersonalRating.title(forServerValue: 10) == "5 Stars")
        #expect(PlexPersonalRating.accessibilityValue(forServerValue: 7) == "3.5 stars")
    }
}
