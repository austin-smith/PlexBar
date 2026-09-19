import SwiftUI

struct PlexPlaybackCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @Bindable var coordinator: PlexPlayerCoordinator
    @Bindable var settingsStore: PlexSettingsStore

    var body: some Commands {
        CommandMenu("Playback") {
            Button("Show Player", systemImage: "play.rectangle") {
                openWindow(id: PlexMainNavigationStore.windowID)
            }
            .disabled(coordinator.presentation == nil)

            Divider()

            Button(
                coordinator.transportAction?.title ?? "Play",
                systemImage: coordinator.transportAction?.systemImage ?? "play.fill",
                action: coordinator.togglePlayback
            )
            // Transport keys are routed by the player so text fields, sliders,
            // and queue controls retain their normal keyboard behavior.
            .disabled(coordinator.transportAction == nil)

            Button("Stop", systemImage: "stop.fill", action: coordinator.stopPlayback)
                .disabled(!coordinator.canStop)

            Divider()

            Menu("Playback Speed") {
                ForEach(PlexPlaybackRate.allCases) { playbackRate in
                    Button {
                        coordinator.selectPlaybackRate(playbackRate)
                    } label: {
                        if coordinator.playbackRate == playbackRate {
                            Label(playbackRate.label, systemImage: "checkmark")
                        } else {
                            Text(playbackRate.label)
                        }
                    }
                }
            }
            .disabled(!coordinator.canChangePlaybackRate)

            Menu("Video Quality") {
                ForEach(PlexVideoQuality.allCases) { videoQuality in
                    Button {
                        coordinator.selectVideoQuality(videoQuality)
                    } label: {
                        if coordinator.videoQualitySelection.selectedQuality == videoQuality {
                            Label(videoQuality.label, systemImage: "checkmark")
                        } else {
                            Text(videoQuality.label)
                        }
                    }
                    .disabled(!coordinator.videoQualitySelection.canSelect(videoQuality))
                }
            }
            .disabled(!coordinator.videoQualitySelection.isVideo)

            Menu("Video Dynamic Range") {
                ForEach(PlexVideoDisplayDynamicRange.allCases) { dynamicRange in
                    Button {
                        settingsStore.videoDynamicRange = dynamicRange
                    } label: {
                        if settingsStore.videoDynamicRange == dynamicRange {
                            Label(dynamicRange.label, systemImage: "checkmark")
                        } else {
                            Text(dynamicRange.label)
                        }
                    }
                }
            }
            .disabled(!coordinator.videoQualitySelection.isVideo)

            Menu("Video Scaling") {
                ForEach(PlexVideoScalingMode.allCases) { scalingMode in
                    Button {
                        settingsStore.videoScalingMode = scalingMode
                    } label: {
                        if settingsStore.videoScalingMode == scalingMode {
                            Label(scalingMode.label, systemImage: "checkmark")
                        } else {
                            Text(scalingMode.label)
                        }
                    }
                }
            }
            .disabled(!coordinator.videoQualitySelection.isVideo)

            if coordinator.serverManagedMediaSelection.hasChoices {
                Divider()

                if !coordinator.serverManagedMediaSelection.audioOptions.isEmpty {
                    Menu("Audio Track") {
                        ForEach(coordinator.serverManagedMediaSelection.audioOptions) { option in
                            Button {
                                coordinator.selectAudioStream(option.id)
                            } label: {
                                if option.isSelected {
                                    Label(option.title, systemImage: "checkmark")
                                } else {
                                    Text(option.title)
                                }
                            }
                        }
                    }
                    .disabled(!coordinator.canChangeServerManagedMediaSelection)
                }

                if !coordinator.serverManagedMediaSelection.subtitleOptions.isEmpty {
                    Menu("Subtitles") {
                        Button {
                            coordinator.selectSubtitleStream(nil)
                        } label: {
                            if coordinator.serverManagedMediaSelection.subtitleOptions
                                .contains(where: \.isSelected) {
                                Text("Off")
                            } else {
                                Label("Off", systemImage: "checkmark")
                            }
                        }

                        Divider()

                        ForEach(coordinator.serverManagedMediaSelection.subtitleOptions) { option in
                            Button {
                                coordinator.selectSubtitleStream(option.id)
                            } label: {
                                if option.isSelected {
                                    Label(option.title, systemImage: "checkmark")
                                } else {
                                    Text(option.title)
                                }
                            }
                        }
                    }
                    .disabled(!coordinator.canChangeServerManagedMediaSelection)
                }
            }

            Toggle(
                "Shuffle",
                isOn: Binding(
                    get: { coordinator.isShuffled },
                    set: { isShuffled in
                        coordinator.setShuffled(isShuffled)
                    }
                )
            )
            .disabled(!coordinator.canChangeShuffle)

            Menu("Repeat") {
                ForEach(PlexPlaybackRepeatMode.allCases) { repeatMode in
                    Button {
                        coordinator.selectRepeatMode(repeatMode)
                    } label: {
                        if coordinator.repeatMode == repeatMode {
                            Label(repeatMode.label, systemImage: "checkmark")
                        } else {
                            Text(repeatMode.label)
                        }
                    }
                    .disabled(repeatMode == .all && !coordinator.canRepeatAll)
                }
            }
            .disabled(!coordinator.canChangeRepeatMode)

            Divider()

            Button(
                "Skip Backward 10 Seconds",
                systemImage: "gobackward.10",
                action: coordinator.skipBackward
            )
            .disabled(!coordinator.canSeek)

            Button(
                "Skip Forward 10 Seconds",
                systemImage: "goforward.10",
                action: coordinator.skipForward
            )
            .disabled(!coordinator.canSeek)

            Divider()

            Button("Previous", action: coordinator.goPrevious)
                .disabled(!coordinator.canGoPrevious)

            Button("Next", action: coordinator.goNext)
                .disabled(!coordinator.canGoNext)
        }
    }
}

private extension PlexPlaybackTransportAction {
    var title: String {
        switch self {
        case .play: "Play"
        case .pause: "Pause"
        }
    }

    var systemImage: String {
        switch self {
        case .play: "play.fill"
        case .pause: "pause.fill"
        }
    }
}
