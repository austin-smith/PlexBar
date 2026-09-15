import AVKit

@MainActor
enum PlexNativePlaybackSpeedConfiguration {
    static let speeds = PlexPlaybackRate.allCases.map { playbackRate in
        AVPlaybackSpeed(
            rate: playbackRate.rawValue,
            localizedName: playbackRate.label
        )
    }

    #if os(macOS)
    static func apply(
        to playerView: AVPlayerView,
        playbackRate: PlexPlaybackRate
    ) {
        applySelectableSpeeds(to: playerView)

        guard let speed = speed(for: playbackRate),
              playerView.selectedSpeed?.rate != speed.rate else {
            return
        }
        playerView.selectSpeed(speed)
    }

    private static func applySelectableSpeeds(to playerView: AVPlayerView) {
        guard playerView.speeds.map(\.rate) != speeds.map(\.rate) else { return }
        playerView.speeds = speeds
    }
    #endif

    #if os(tvOS)
    static func apply(to playerViewController: AVPlayerViewController) {
        guard playerViewController.speeds.map(\.rate) != speeds.map(\.rate) else { return }
        playerViewController.speeds = speeds
    }
    #endif

    static func speed(for playbackRate: PlexPlaybackRate) -> AVPlaybackSpeed? {
        speeds.first { speed in
            abs(speed.rate - playbackRate.rawValue) < 0.001
        }
    }

    static func playbackRate(for speed: AVPlaybackSpeed?) -> PlexPlaybackRate? {
        guard let speed else {
            return nil
        }
        return PlexPlaybackRate(remoteCommandValue: speed.rate)
    }
}
