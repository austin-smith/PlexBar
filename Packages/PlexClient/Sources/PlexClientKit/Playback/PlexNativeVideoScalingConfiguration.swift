import AVFoundation
import AVKit

@MainActor
public enum PlexNativeVideoScalingConfiguration {
    #if os(macOS)
    public static func apply(
        to playerView: AVPlayerView,
        scalingMode: PlexVideoScalingMode
    ) {
        let videoGravity = scalingMode.avVideoGravity
        guard playerView.videoGravity != videoGravity else { return }
        playerView.videoGravity = videoGravity
    }
    #endif

    #if os(tvOS)
    public static func apply(
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
    public var avVideoGravity: AVLayerVideoGravity {
        switch self {
        case .fit: .resizeAspect
        case .fill: .resizeAspectFill
        }
    }
}
