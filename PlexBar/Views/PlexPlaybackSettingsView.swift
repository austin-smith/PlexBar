import SwiftUI

struct PlexPlaybackSettingsView: View {
    @Bindable var settingsStore: PlexSettingsStore

    var body: some View {
        Form {
            qualitySection
            videoSection
            startingAndResumingSection
            autoplaySection
            skippingSection
        }
        .formStyle(.grouped)
    }

    private var qualitySection: some View {
        Section {
            videoQualityPicker("Local Video Quality", selection: $settingsStore.localVideoQuality)
            videoQualityPicker("Remote Video Quality", selection: $settingsStore.remoteVideoQuality)
            Toggle(isOn: $settingsStore.qualitySuggestionsEnabled) {
                SettingsControlLabel(
                    title: "Suggest Quality Changes",
                    detail: "Ask before adjusting quality when playback stalls or your connection improves."
                )
            }
        } header: {
            Text("Quality")
        } footer: {
            Text("Local applies on your server’s network; remote applies elsewhere. Suggestions stay within the quality you choose.")
        }
    }

    private var videoSection: some View {
        Section {
            Picker(selection: $settingsStore.videoDynamicRange) {
                ForEach(PlexVideoDisplayDynamicRange.allCases) { dynamicRange in
                    Text(dynamicRange.label).tag(dynamicRange)
                }
            } label: {
                SettingsControlLabel(title: "Dynamic Range", detail: dynamicRangeExplanation)
            }

            Picker(selection: $settingsStore.videoScalingMode) {
                ForEach(PlexVideoScalingMode.allCases) { scalingMode in
                    Text(scalingMode.label).tag(scalingMode)
                }
            } label: {
                SettingsControlLabel(
                    title: "Video Scaling",
                    detail: "Fit shows the whole picture. Fill crops the edges to fill the player."
                )
            }
        } header: {
            Text("Video Display")
        }
    }

    private var startingAndResumingSection: some View {
        Section {
            Picker(selection: $settingsStore.cinemaPreplayPreference) {
                ForEach(PlexCinemaPreplayPreference.allCases) { preference in
                    Text(preference.label).tag(preference)
                }
            } label: {
                SettingsControlLabel(
                    title: "Before Movies",
                    detail: "Play trailers or your server’s opening video (pre-roll). Off skips both."
                )
            }

            Picker(
                selection: Binding(
                    get: { settingsStore.rewindOnResume.seconds },
                    set: { settingsStore.rewindOnResume = PlexRewindOnResume(seconds: $0) }
                )
            ) {
                Text("Off").tag(0)
                ForEach([2, 5, 10, 15, 30], id: \.self) { seconds in
                    Text("\(seconds) seconds").tag(seconds)
                }
            } label: {
                SettingsControlLabel(
                    title: "Rewind on Resume",
                    detail: "Go back a few seconds when resuming paused playback."
                )
            }
            .pickerStyle(.menu)
        } header: {
            Text("Starting and Resuming")
        }
    }

    private var autoplaySection: some View {
        Section {
            Toggle("Auto Play Up Next", isOn: $settingsStore.autoplayUpNext)

            Picker("Up Next Countdown", selection: $settingsStore.autoplayCountdown) {
                ForEach(PlexAutoplayCountdown.allCases) { countdown in
                    Text(countdown.label).tag(countdown)
                }
            }
            .disabled(!settingsStore.autoplayUpNext)

            Picker(selection: $settingsStore.passoutProtection) {
                ForEach(PlexPassoutProtection.allCases) { protection in
                    Text(protection.label).tag(protection)
                }
            } label: {
                SettingsControlLabel(
                    title: "Inactivity Reminder",
                    detail: "Ask whether you’re still watching before continuing a long viewing session."
                )
            }
            .disabled(!settingsStore.autoplayUpNext)
        } header: {
            Text("Autoplay")
        } footer: {
            Text("The countdown and inactivity reminder apply when Auto Play Up Next is on.")
        }
    }

    private var dynamicRangeExplanation: String {
        switch settingsStore.videoDynamicRange {
        case .automatic: "Let the system choose the display’s dynamic range."
        case .standard: "Display video in standard dynamic range."
        case .constrainedHigh: "Limit HDR intensity when showing video alongside standard content."
        case .high: "Allow the full high dynamic range available on your display."
        }
    }

    private var skippingSection: some View {
        Section {
            playbackMarkerBehaviorPicker("Intros", selection: $settingsStore.skipIntroBehavior)
            playbackMarkerBehaviorPicker("Ads in Recordings", selection: $settingsStore.skipAdsBehavior)
            playbackMarkerBehaviorPicker("Credits", selection: $settingsStore.skipCreditsBehavior)
        } header: {
            Text("Skipping")
        } footer: {
            Text("Skip controls are available when your Plex server identifies these sections in a video.")
        }
    }

    private func videoQualityPicker(_ title: String, selection: Binding<PlexVideoQuality>) -> some View {
        Picker(title, selection: selection) {
            ForEach(PlexVideoQuality.allCases) { quality in
                Text(quality.label).tag(quality)
            }
        }
    }

    private func playbackMarkerBehaviorPicker(
        _ title: String,
        selection: Binding<PlexPlaybackMarkerBehavior>
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(PlexPlaybackMarkerBehavior.allCases) { behavior in
                Text(behavior.label).tag(behavior)
            }
        }
    }
}
