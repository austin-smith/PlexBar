import PlexModels
import Foundation
import SwiftUI
import Testing
@testable import PlexBar

struct PlexAccessibilityPresentationTests {
    @Test func increasedContrastSubduesArtworkAndStrengthensTheSemanticFade() {
        for colorScheme in [ColorScheme.light, .dark] {
            let standard = PlexArtworkBackdropStyle(
                colorScheme: colorScheme,
                contrast: .standard
            )
            let increased = PlexArtworkBackdropStyle(
                colorScheme: colorScheme,
                contrast: .increased
            )

            #expect(increased.paletteOpacity < standard.paletteOpacity)
            #expect(increased.topFadeOpacity > standard.topFadeOpacity)
            #expect(increased.middleFadeOpacity > standard.middleFadeOpacity)
            #expect(increased.bottomFadeOpacity > standard.bottomFadeOpacity)
        }
    }

    @Test func backdropNeverRemovesTheSemanticWindowBackground() {
        for colorScheme in [ColorScheme.light, .dark] {
            for contrast in [ColorSchemeContrast.standard, .increased] {
                let style = PlexArtworkBackdropStyle(
                    colorScheme: colorScheme,
                    contrast: contrast
                )

                #expect(style.topFadeOpacity > 0)
                #expect(style.middleFadeOpacity >= style.topFadeOpacity)
                #expect(style.bottomFadeOpacity >= style.middleFadeOpacity)
                #expect(style.bottomFadeOpacity <= 1)
            }
        }
    }

    @Test func increasedContrastStrengthensCinematicHeroReadabilityWithoutChangingLayout() {
        let standard = PlexCinematicHeroStyle(contrast: .standard)
        let increased = PlexCinematicHeroStyle(contrast: .increased)

        #expect(increased.blurSaturation < standard.blurSaturation)
        #expect(increased.blurDarkeningOpacity > standard.blurDarkeningOpacity)
        #expect(increased.upperScrimOpacity > standard.upperScrimOpacity)
        #expect(increased.contentScrimOpacity > standard.contentScrimOpacity)
        #expect(increased.lowerScrimOpacity > standard.lowerScrimOpacity)
    }

    @Test func increasedContrastStrengthensOnlyThePlayerHUDBackgroundScrim() {
        let standard = PlexPlayerOverlayStyle(contrast: .standard)
        let increased = PlexPlayerOverlayStyle(contrast: .increased)

        #expect(standard.backgroundScrimOpacity == 0.14)
        #expect(increased.backgroundScrimOpacity > standard.backgroundScrimOpacity)
        #expect(increased.backgroundScrimOpacity < 1)
    }

    @Test func mediaCardsExposeWatchedProgressAndUnwatchedStateWithoutRelyingOnColor() throws {
        let watched = try decodeMediaItem(
            #"{"ratingKey":"1","type":"movie","title":"Watched","viewCount":1}"#
        )
        let inProgress = try decodeMediaItem(
            #"{"ratingKey":"2","type":"episode","title":"In Progress","duration":400000,"viewOffset":100000}"#
        )
        let unwatched = try decodeMediaItem(
            #"{"ratingKey":"3","type":"movie","title":"Unwatched","viewCount":0}"#
        )
        let unsupported = try decodeMediaItem(
            #"{"ratingKey":"4","type":"clip","title":"Extra","viewCount":0}"#
        )

        #expect(watched.watchStateAccessibilityValue == "Watched")
        #expect(inProgress.watchStateAccessibilityValue == "25% watched")
        #expect(unwatched.watchStateAccessibilityValue == "Unwatched")
        #expect(unsupported.watchStateAccessibilityValue == nil)
    }

    private func decodeMediaItem(_ json: String) throws -> PlexMediaItem {
        try JSONDecoder().decode(PlexMediaItem.self, from: Data(json.utf8))
    }
}
