import SwiftUI

struct PlexNativeTrackMenus: View {
    let options: PlexPlayerMediaOptions

    var body: some View {
        if options.audio.count > 1 {
            Menu("Audio Track") {
                ForEach(options.audio) { option in
                    Button { options.selectAudio(option) } label: {
                        if options.selectedAudioID == option.id {
                            Label(option.title, systemImage: "checkmark")
                        } else { Text(option.title) }
                    }
                }
            }
        }
        if !options.subtitles.isEmpty {
            Menu("Subtitles") {
                if options.allowsSubtitlesOff {
                    Button { options.selectSubtitle(nil) } label: {
                        if options.selectedSubtitleID == nil {
                            Label("Off", systemImage: "checkmark")
                        } else { Text("Off") }
                    }
                }
                ForEach(options.subtitles) { option in
                    Button { options.selectSubtitle(option) } label: {
                        if options.selectedSubtitleID == option.id {
                            Label(option.title, systemImage: "checkmark")
                        } else { Text(option.title) }
                    }
                }
            }
        }
    }
}
