import AVKit
import SwiftUI

struct PlexPlaybackRoutePicker: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.isRoutePickerButtonBordered = false
        PlexPlaybackRoutePickerConfiguration.apply(
            to: routePickerView,
            player: player
        )
        return routePickerView
    }

    func updateNSView(_ routePickerView: AVRoutePickerView, context: Context) {
        PlexPlaybackRoutePickerConfiguration.apply(
            to: routePickerView,
            player: player
        )
    }
}
