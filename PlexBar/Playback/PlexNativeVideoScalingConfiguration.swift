import AVFoundation
import AVKit

@MainActor
enum PlexNativeVideoScalingConfiguration {
    #if os(macOS)
    static func apply(
        to playerView: AVPlayerView,
        scalingMode: PlexVideoScalingMode
    ) {
        let videoGravity = scalingMode.avVideoGravity
        guard playerView.videoGravity != videoGravity else { return }
        playerView.videoGravity = videoGravity
    }
    #endif

    #if os(tvOS)
    static func apply(
        to playerViewController: AVPlayerViewController,
        scalingMode: PlexVideoScalingMode
    ) {
        let videoGravity = scalingMode.avVideoGravity
        guard playerViewController.videoGravity != videoGravity else { return }
        playerViewController.videoGravity = videoGravity
    }
    #endif
}

extension PlexVideoScalingMode {
    var avVideoGravity: AVLayerVideoGravity {
        switch self {
        case .fit: .resizeAspect
        case .fill: .resizeAspectFill
        }
    }
}
