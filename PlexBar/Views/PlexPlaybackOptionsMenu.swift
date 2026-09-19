import SwiftUI

struct PlexPlaybackOptionsMenu: View {
    let session: PlexPlayerSessionModel
    let settingsStore: PlexSettingsStore
    let mediaOptions: PlexPlayerMediaOptions
    let coordinator: PlexPlayerCoordinator
    let showInfo: () -> Void

    var body: some View {
        Menu {
            if session.videoQualitySelection.isVideo {
                videoQualityMenu
                videoDynamicRangeMenu
                videoScalingMenu
                Divider()
            }

            playbackSpeedMenu
            PlexNativeTrackMenus(options: mediaOptions)
                .disabled(session.isLoading || session.isUpdatingQueue)

            if session.serverManagedMediaSelection.hasChoices {
                Divider()
                serverManagedMediaSelectionMenus
            }

            Divider()
            Toggle("Shuffle", isOn: Binding(
                get: { coordinator.isShuffled }, set: coordinator.setShuffled
            ))
            .disabled(!coordinator.canChangeShuffle)
            Menu("Repeat") {
                ForEach(PlexPlaybackRepeatMode.allCases) { mode in
                    Button { coordinator.selectRepeatMode(mode) } label: {
                        if coordinator.repeatMode == mode {
                            Label(mode.label, systemImage: "checkmark")
                        } else { Text(mode.label) }
                    }
                    .disabled(!coordinator.canChangeRepeatMode || (mode == .all && !coordinator.canRepeatAll))
                }
            }
            Divider()
            Button("Playback Info", systemImage: "info.circle", action: showInfo)
        } label: {
            Label("Playback Options", systemImage: "gearshape")
        }
        .menuStyle(.button)
        .fixedSize()
        .help("Choose Playback Options")
        .accessibilityLabel("Playback Options")
    }

    private var videoQualityMenu: some View {
        Menu("Video Quality") {
            ForEach(PlexVideoQuality.allCases) { quality in
                Button {
                    session.selectVideoQuality(quality)
                } label: {
                    if session.videoQualitySelection.selectedQuality == quality {
                        Label(quality.label, systemImage: "checkmark")
                    } else {
                        Text(quality.label)
                    }
                }
                .disabled(!session.videoQualitySelection.canSelect(quality))
            }
        }
    }

    private var videoDynamicRangeMenu: some View {
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
    }

    private var videoScalingMenu: some View {
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
    }

    private var playbackSpeedMenu: some View {
        Menu("Playback Speed") {
            ForEach(PlexPlaybackRate.allCases) { playbackRate in
                Button {
                    session.selectPlaybackRate(playbackRate)
                } label: {
                    if session.engine.playbackRate == playbackRate {
                        Label(playbackRate.label, systemImage: "checkmark")
                    } else {
                        Text(playbackRate.label)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var serverManagedMediaSelectionMenus: some View {
        let selection = session.serverManagedMediaSelection

        if !selection.audioOptions.isEmpty {
            Menu("Audio Track") {
                ForEach(selection.audioOptions) { option in
                    Button {
                        session.selectAudioStream(option.id)
                    } label: {
                        if option.isSelected {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            }
            .disabled(!session.canChangeMediaSelection)
        }

        if !selection.subtitleOptions.isEmpty {
            Menu("Subtitles") {
                Button {
                    session.selectSubtitleStream(nil)
                } label: {
                    if selection.subtitleOptions.contains(where: \.isSelected) {
                        Text("Off")
                    } else {
                        Label("Off", systemImage: "checkmark")
                    }
                }

                ForEach(selection.subtitleOptions) { option in
                    Button {
                        session.selectSubtitleStream(option.id)
                    } label: {
                        if option.isSelected {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            }
            .disabled(!session.canChangeMediaSelection)
        }
    }
}
