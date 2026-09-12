import Testing
@testable import PlexBar

struct PlexNativeSkippingConfigurationTests {
    @Test
    func videoKeepsTimeSkippingWhenTheQueueHasAdjacentItems() {
        let configuration = PlexNativeSkippingConfiguration(
            mediaKind: .video,
            canMovePrevious: true,
            canMoveNext: true,
            controlsEnabled: true
        )

        #expect(configuration.mode == .time)
        #expect(configuration.isBackwardEnabled)
        #expect(configuration.isForwardEnabled)
    }

    @Test
    func musicUsesOnlyAvailableQueueDirections() {
        let configuration = PlexNativeSkippingConfiguration(
            mediaKind: .music,
            canMovePrevious: false,
            canMoveNext: true,
            controlsEnabled: true
        )

        #expect(configuration.mode == .item)
        #expect(!configuration.isBackwardEnabled)
        #expect(configuration.isForwardEnabled)
    }

    @Test
    func musicWithoutAdjacentItemsKeepsTimeSkipping() {
        let configuration = PlexNativeSkippingConfiguration(
            mediaKind: .music,
            canMovePrevious: false,
            canMoveNext: false,
            controlsEnabled: true
        )

        #expect(configuration.mode == .time)
        #expect(configuration.isBackwardEnabled)
        #expect(configuration.isForwardEnabled)
    }

    @Test
    func busyPlaybackDisablesEverySkippingDirection() {
        for mediaKind in [PlexPlaybackMediaKind.video, .music] {
            let configuration = PlexNativeSkippingConfiguration(
                mediaKind: mediaKind,
                canMovePrevious: true,
                canMoveNext: true,
                controlsEnabled: false
            )

            #expect(!configuration.isBackwardEnabled)
            #expect(!configuration.isForwardEnabled)
        }
    }
}
