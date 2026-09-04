import AVFoundation
import CoreMedia
import VideoToolbox

enum NativePlaybackCapabilityProbe {
    static func current() -> PlexPlaybackCapabilities {
        capabilities(
            hardwareDecodeSupported: VTIsHardwareDecodeSupported,
            playableExtendedMIMEType: AVURLAsset.isPlayableExtendedMIMEType
        )
    }

    static func capabilities(
        hardwareDecodeSupported: (CMVideoCodecType) -> Bool,
        playableExtendedMIMEType: (String) -> Bool
    ) -> PlexPlaybackCapabilities {
        let videoCodecs: [String] = videoCandidates.compactMap { candidate in
            guard hardwareDecodeSupported(candidate.codecType),
                  candidate.extendedMIMETypes.allSatisfy(playableExtendedMIMEType) else {
                return nil
            }
            return candidate.plexCodec
        }
        let audioCodecs: [String] = audioCandidates.compactMap { candidate in
            playableExtendedMIMEType(candidate.extendedMIMEType)
                ? candidate.plexCodec
                : nil
        }
        let musicProfiles: [PlexMusicDirectPlayProfile] = musicCandidates.compactMap { candidate in
            guard playableExtendedMIMEType(candidate.extendedMIMEType) else {
                return nil
            }
            return PlexMusicDirectPlayProfile(
                container: candidate.plexContainer,
                audioCodec: candidate.plexCodec
            )
        }

        return PlexPlaybackCapabilities(
            directPlayContainers: ["m4v", "mov", "mp4"],
            directPlayVideoCodecs: Set(videoCodecs),
            directPlayAudioCodecs: Set(audioCodecs),
            directPlayMusicProfiles: Set(musicProfiles)
        )
    }

    private struct VideoCandidate {
        let plexCodec: String
        let codecType: CMVideoCodecType
        let extendedMIMETypes: [String]
    }

    private struct AudioCandidate {
        let plexCodec: String
        let extendedMIMEType: String
    }

    private struct MusicCandidate {
        let plexContainer: String
        let plexCodec: String
        let extendedMIMEType: String
    }

    private static let videoCandidates = [
        VideoCandidate(
            plexCodec: "h264",
            codecType: kCMVideoCodecType_H264,
            extendedMIMETypes: [
                #"video/mp4; codecs="avc1.640028, mp4a.40.2""#
            ]
        ),
        VideoCandidate(
            plexCodec: "hevc",
            codecType: kCMVideoCodecType_HEVC,
            extendedMIMETypes: [
                #"video/mp4; codecs="hvc1.1.6.L120.B0, mp4a.40.2""#,
                #"video/mp4; codecs="hvc1.2.4.L153.B0, mp4a.40.2""#,
            ]
        ),
        VideoCandidate(
            plexCodec: "av1",
            codecType: kCMVideoCodecType_AV1,
            extendedMIMETypes: [
                #"video/mp4; codecs="av01.0.08M.08, mp4a.40.2""#
            ]
        ),
    ]

    private static let audioCandidates = [
        AudioCandidate(plexCodec: "aac", extendedMIMEType: #"video/mp4; codecs="mp4a.40.2""#),
        AudioCandidate(plexCodec: "ac3", extendedMIMEType: #"video/mp4; codecs="ac-3""#),
        AudioCandidate(plexCodec: "eac3", extendedMIMEType: #"video/mp4; codecs="ec-3""#),
        AudioCandidate(plexCodec: "alac", extendedMIMEType: #"video/mp4; codecs="alac""#),
        AudioCandidate(plexCodec: "flac", extendedMIMEType: #"video/mp4; codecs="fLaC""#),
        AudioCandidate(plexCodec: "opus", extendedMIMEType: #"video/mp4; codecs="Opus""#),
    ]

    private static let musicCandidates = [
        MusicCandidate(
            plexContainer: "aac",
            plexCodec: "aac",
            extendedMIMEType: #"audio/aac; codecs="mp4a.40.2""#
        ),
        MusicCandidate(
            plexContainer: "mp3",
            plexCodec: "mp3",
            extendedMIMEType: #"audio/mpeg; codecs="mp3""#
        ),
        MusicCandidate(
            plexContainer: "mp4",
            plexCodec: "aac",
            extendedMIMEType: #"audio/mp4; codecs="mp4a.40.2""#
        ),
        MusicCandidate(
            plexContainer: "mp4",
            plexCodec: "alac",
            extendedMIMEType: #"audio/mp4; codecs="alac""#
        ),
        MusicCandidate(
            plexContainer: "ogg",
            plexCodec: "opus",
            extendedMIMEType: #"audio/ogg; codecs="opus""#
        ),
    ]
}
