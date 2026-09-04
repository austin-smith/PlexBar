import CoreMedia
import Testing
@testable import PlexBar

@Suite struct NativePlaybackCapabilityProbeTests {
    @Test func requiresHardwareAndContainerCodecSupportForVideo() {
        let capabilities = NativePlaybackCapabilityProbe.capabilities(
            hardwareDecodeSupported: { codec in
                codec == kCMVideoCodecType_H264 || codec == kCMVideoCodecType_AV1
            },
            playableExtendedMIMEType: { mimeType in
                !mimeType.contains("av01")
            }
        )

        #expect(capabilities.directPlayVideoCodecs == ["h264"])
    }

    @Test func advertisesAV1OnlyWhenBothNativeGatesPass() {
        let capabilities = NativePlaybackCapabilityProbe.capabilities(
            hardwareDecodeSupported: { $0 == kCMVideoCodecType_AV1 },
            playableExtendedMIMEType: { $0.contains("av01") || $0.contains("mp4a.40.2") }
        )

        #expect(capabilities.directPlayVideoCodecs == ["av1"])
        #expect(capabilities.clientProfileExtra(for: .video).contains("videoCodec=av1"))
    }

    @Test func derivesVideoAudioCodecsFromAVFoundationPlayability() {
        let capabilities = NativePlaybackCapabilityProbe.capabilities(
            hardwareDecodeSupported: { _ in false },
            playableExtendedMIMEType: { mimeType in
                mimeType.contains("mp4a.40.2") || mimeType.contains("ec-3") || mimeType.contains("Opus")
            }
        )

        #expect(capabilities.directPlayAudioCodecs == ["aac", "eac3", "opus"])
    }

    @Test func derivesExactMusicContainerCodecPairsFromAudioMIMEPlayability() {
        let capabilities = NativePlaybackCapabilityProbe.capabilities(
            hardwareDecodeSupported: { _ in false },
            playableExtendedMIMEType: { mimeType in
                mimeType == #"audio/mpeg; codecs="mp3""#
                    || mimeType == #"audio/mp4; codecs="alac""#
            }
        )

        #expect(capabilities.directPlayMusicProfiles == [
            PlexMusicDirectPlayProfile(container: "mp3", audioCodec: "mp3"),
            PlexMusicDirectPlayProfile(container: "mp4", audioCodec: "alac"),
        ])
        let profile = capabilities.clientProfileExtra(for: .music)
        #expect(profile.contains("type=musicProfile&container=mp3"))
        #expect(profile.contains("type=musicProfile&container=mp4"))
        #expect(!profile.contains("type=videoProfile"))
    }

    @Test func downloadProfilesUseNativeHTTPMP4ConversionTargets() {
        let capabilities = PlexPlaybackCapabilities(
            directPlayContainers: ["mp4"],
            directPlayVideoCodecs: ["h264"],
            directPlayAudioCodecs: ["aac"],
            directPlayMusicProfiles: [
                PlexMusicDirectPlayProfile(container: "mp4", audioCodec: "aac")
            ]
        )

        let video = capabilities.downloadClientProfileExtra(for: .video)
        #expect(video.contains("type=videoProfile&context=static&protocol=http"))
        #expect(video.contains(
            "container=mp4&videoCodec=h264&audioCodec=aac&subtitleCodec=mov_text&replace=true"
        ))

        let music = capabilities.downloadClientProfileExtra(for: .music)
        #expect(music.contains("type=musicProfile&context=static&protocol=http"))
        #expect(music.contains("container=mp4&audioCodec=aac&replace=true"))
    }
}
