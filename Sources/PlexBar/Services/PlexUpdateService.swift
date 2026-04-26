import Foundation
import Observation
import Sparkle

@MainActor
@Observable
final class PlexUpdateService {
    private let updaterController: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckForUpdatesObservation: NSKeyValueObservation?
    private(set) var canCheckForUpdates = false

    init() {
#if DEBUG
        updaterController = nil
#else
        let updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.updaterController = updaterController

        canCheckForUpdatesObservation = updaterController.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            Task { @MainActor in
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
#endif
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}
