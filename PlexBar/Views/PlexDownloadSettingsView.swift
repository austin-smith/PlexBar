import PlexClientKit
import SwiftUI

struct PlexDownloadSettingsView: View {
    @Bindable var settingsStore: PlexSettingsStore

    var body: some View {
        Form {
            Section {
                Picker("Video Quality", selection: $settingsStore.downloadVideoQuality) {
                    ForEach(PlexDownloadVideoQuality.allCases) { quality in
                        Text(quality.label)
                            .tag(quality)
                    }
                }

                Picker("Music Quality", selection: $settingsStore.downloadMusicQuality) {
                    ForEach(PlexMusicQuality.allCases) { quality in
                        Text(quality.label)
                            .tag(quality)
                    }
                }
            } header: {
                Text("Quality")
            } footer: {
                Text("Applies to new downloads. Existing downloads and streaming quality stay unchanged.")
            }

            Section {
                Picker(selection: $settingsStore.downloadSubtitlePreference) {
                    ForEach(PlexDownloadSubtitlePreference.allCases) { preference in
                        Text(preference.label)
                            .tag(preference)
                    }
                } label: {
                    SettingsControlLabel(title: "Selected Subtitles", detail: subtitleExplanation)
                }
            } header: {
                Text("Subtitles")
            } footer: {
                Text("Applies to subtitles selected for new downloads.")
            }
        }
        .formStyle(.grouped)
    }

    private var subtitleExplanation: String {
        switch settingsStore.downloadSubtitlePreference {
        case .selectable:
            "Selected subtitles are stored as a switchable text track. Complex formatting may be simplified."
        case .burn:
            "Selected subtitles are rendered permanently into downloaded video."
        case .none:
            "Selected subtitles are not included in new downloads."
        }
    }
}
