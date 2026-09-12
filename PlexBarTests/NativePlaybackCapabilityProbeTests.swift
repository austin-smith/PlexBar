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

    @Test(arguments: [
        (true, true, "h264,hevc"),
        (false, true, "h264"),
        (true, false, "h264"),
    ])
    func hlsPreservesHEVCOnlyWithNativeDecodeAndMP4Support(
        hardwareSupportsHEVC: Bool,
        mp4SupportsHEVC: Bool,
        expectedVideoCodecs: String
    ) {
        let capabilities = NativePlaybackCapabilityProbe.capabilities(
            hardwareDecodeSupported: { codec in
                codec != kCMVideoCodecType_HEVC || hardwareSupportsHEVC
            },
            playableExtendedMIMEType: { mimeType in
                !mimeType.contains("hvc1") || mp4SupportsHEVC
            }
        )

        let profile = capabilities.clientProfileExtra(for: .video)
        #expect(profile.contains(
            "add-transcode-target(type=videoProfile&context=streaming&protocol=hls" +
                "&container=mp4&videoCodec=\(expectedVideoCodecs)&audioCodec=aac&replace=true)"
        ))
        // A codec supported for files (such as AV1) is not automatically an HLS codec.
        #expect(!profile.contains("container=mp4&videoCodec=h264,hevc,av1"))
        #expect(!profile.contains("container=mpegts"))
        #expect(capabilities.clientProfileExtra(for: .music).contains("container=mpegts"))
    }

    @Test func hlsDolbySupportRequiresTheMP4ContainerUsedForDelivery() {
        let capabilities = NativePlaybackCapabilityProbe.capabilities(
            hardwareDecodeSupported: { _ in true },
            playableExtendedMIMEType: { $0.hasPrefix("video/mp2t;") }
        )

        #expect(capabilities.hlsStreamingAudioCodecs.isEmpty)
    }

    @Test func advertisesOnlyVerifiedDolbyCodecsForHLSStreaming() {
        let capabilities = NativePlaybackCapabilityProbe.capabilities(
            hardwareDecodeSupported: { _ in false },
            playableExtendedMIMEType: { mimeType in
                mimeType == #"video/mp4; codecs="avc1.640028, ec-3""#
            }
        )

        #expect(capabilities.hlsStreamingAudioCodecs == ["eac3"])
        #expect(capabilities.clientProfileExtra(for: .video).contains(
            "add-transcode-target-codec(type=videoProfile&context=streaming" +
                "&protocol=hls&audioCodec=eac3)"
        ))
    }

    @Test func omitsHLSAudioAugmentationWithoutNativeContainerCodecSupport() {
        let capabilities = NativePlaybackCapabilityProbe.capabilities(
            hardwareDecodeSupported: { _ in false },
            playableExtendedMIMEType: { _ in false }
        )

        #expect(capabilities.hlsStreamingAudioCodecs.isEmpty)
        #expect(!capabilities.clientProfileExtra(for: .video).contains(
            "add-transcode-target-codec"
        ))
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
