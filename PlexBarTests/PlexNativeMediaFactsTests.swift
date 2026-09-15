import AudioToolbox
import CoreMedia
import Foundation
import Testing
@testable import PlexBar

struct PlexNativeMediaFactsTests {
    @Test func extractsDeliveredHDRVideoAndMultichannelAudioFacts() throws {
        let videoDescription = try makeVideoDescription(
            codec: kCMVideoCodecType_HEVC,
            width: 3840,
            height: 2160,
            transferFunction: kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ,
            includesHDR10StaticMetadata: true
        )
        let audioDescription = try makeAudioDescription(
            formatID: kAudioFormatEnhancedAC3,
            channelCount: 6,
            layoutTag: kAudioChannelLayoutTag_MPEG_5_1_A
        )

        let facts = try #require(PlexNativeMediaInspector.facts(
            videoFormatDescription: videoDescription,
            audioFormatDescription: audioDescription,
            videoFrameRate: 23.976,
            videoBitRate: 18_500_000,
            audioBitRate: 640_000
        ))

        #expect(facts.videoWidth == 3840)
        #expect(facts.videoHeight == 2160)
        #expect(facts.videoFrameRate == 23.976)
        #expect(facts.videoCodec == "HEVC")
        #expect(facts.dynamicRange == .hdr10)
        #expect(facts.videoBitRate == 18_500_000)
        #expect(facts.audioCodec == "E-AC-3")
        #expect(facts.audioChannelCount == 6)
        #expect(facts.audioLayout == .surround5_1)
        #expect(facts.audioSampleRate == 48_000)
        #expect(facts.audioBitRate == 640_000)
        #expect(facts.displayComponents == [
            "3840 × 2160",
            "23.976 fps",
            "HEVC",
            "HDR10",
            "18.5 Mbps video",
            "E-AC-3 5.1",
            "48 kHz",
            "640 kbps audio",
        ])
        #expect(facts.compactDisplayComponents == [
            "3840 × 2160",
            "HEVC",
            "HDR10",
            "E-AC-3 5.1",
        ])
        #expect(facts.diagnosticFacts.map { "\($0.label): \($0.value)" } == [
            "Resolution: 3840 × 2160",
            "Frame Rate: 23.976 fps",
            "Video Codec: HEVC",
            "Dynamic Range: HDR10",
            "Video Data Rate: 18.5 Mbps",
            "Audio Codec: E-AC-3",
            "Channels: 5.1",
            "Sample Rate: 48 kHz",
            "Audio Data Rate: 640 kbps",
        ])
        #expect(Set(facts.diagnosticFacts.map(\.id)).count == facts.diagnosticFacts.count)
        #expect(facts.videoDiagnosticFacts.map(\.kind) == [
            .resolution,
            .frameRate,
            .videoCodec,
            .dynamicRange,
            .videoBitRate,
        ])
        #expect(facts.audioDiagnosticFacts.map(\.kind) == [
            .audioCodec,
            .channels,
            .sampleRate,
            .audioBitRate,
        ])
    }

    @Test func reportsDeliveredAtmosLayoutWithoutInferringItFromChannelCount() throws {
        let atmosDescription = try makeAudioDescription(
            formatID: kAudioFormatEnhancedAC3,
            channelCount: 12,
            layoutTag: kAudioChannelLayoutTag_Atmos_7_1_4
        )
        let atmosFacts = try #require(PlexNativeMediaInspector.facts(
            videoFormatDescription: nil,
            audioFormatDescription: atmosDescription
        ))

        #expect(atmosFacts.audioLayout == .atmos7_1_4)
        #expect(atmosFacts.displayComponents == ["E-AC-3 Atmos 7.1.4", "48 kHz"])

        let unspecifiedDescription = try makeAudioDescription(
            formatID: kAudioFormatEnhancedAC3,
            channelCount: 12
        )
        let unspecifiedFacts = try #require(PlexNativeMediaInspector.facts(
            videoFormatDescription: nil,
            audioFormatDescription: unspecifiedDescription
        ))

        #expect(unspecifiedFacts.audioLayout == nil)
        #expect(unspecifiedFacts.displayComponents == ["E-AC-3 12 ch", "48 kHz"])
    }

    @Test func invalidTrackRatesNeverBecomePlaybackFacts() {
        #expect(PlexNativeMediaInspector.facts(
            videoFormatDescription: nil,
            audioFormatDescription: nil,
            videoFrameRate: .nan,
            videoBitRate: -.infinity,
            audioBitRate: 0
        ) == nil)
    }

    @Test func formatsFractionalAudioSampleRatesWithoutRoundingAwayFacts() throws {
        let description = try makeAudioDescription(
            formatID: kAudioFormatMPEG4AAC,
            channelCount: 2,
            sampleRate: 44_100
        )
        let facts = try #require(PlexNativeMediaInspector.facts(
            videoFormatDescription: nil,
            audioFormatDescription: description,
            audioBitRate: 256_500
        ))

        #expect(facts.audioSampleRate == 44_100)
        #expect(facts.displayComponents == [
            "AAC Stereo",
            "44.1 kHz",
            "256.5 kbps audio",
        ])
    }

    @Test func mapsOnlyAuthoritativeSurroundLayoutTags() {
        #expect(
            PlexNativeMediaInspector.audioLayout(for: kAudioChannelLayoutTag_MPEG_5_1_D)
                == .surround5_1
        )
        #expect(
            PlexNativeMediaInspector.audioLayout(for: kAudioChannelLayoutTag_EAC3_6_1_A)
                == .surround6_1
        )
        #expect(
            PlexNativeMediaInspector.audioLayout(for: kAudioChannelLayoutTag_DTS_7_1)
                == .surround7_1
        )
        #expect(
            PlexNativeMediaInspector.audioLayout(for: kAudioChannelLayoutTag_DiscreteInOrder | 6)
                == nil
        )
    }

    @Test func distinguishesDolbyVisionHLGAndExplicitSDR() {
        #expect(PlexNativeMediaInspector.dynamicRange(
            mediaSubtype: kCMVideoCodecType_DolbyVisionHEVC,
            transferFunction: nil,
            hasHDR10StaticMetadata: false
        ) == .dolbyVision)
        #expect(PlexNativeMediaInspector.dynamicRange(
            mediaSubtype: kCMVideoCodecType_HEVC,
            transferFunction: kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG,
            hasHDR10StaticMetadata: false
        ) == .hlg)
        #expect(PlexNativeMediaInspector.dynamicRange(
            mediaSubtype: kCMVideoCodecType_H264,
            transferFunction: kCMFormatDescriptionTransferFunction_ITU_R_709_2,
            hasHDR10StaticMetadata: false
        ) == .sdr)
    }

    @Test func doesNotCallPQHDR10WithoutStaticMetadata() {
        #expect(PlexNativeMediaInspector.dynamicRange(
            mediaSubtype: kCMVideoCodecType_HEVC,
            transferFunction: kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ,
            hasHDR10StaticMetadata: false
        ) == .hdrPQ)
    }

    private func makeVideoDescription(
        codec: CMVideoCodecType,
        width: Int32,
        height: Int32,
        transferFunction: CFString,
        includesHDR10StaticMetadata: Bool
    ) throws -> CMVideoFormatDescription {
        var extensions: [String: Any] = [
            kCMFormatDescriptionExtension_TransferFunction as String: transferFunction,
        ]
        if includesHDR10StaticMetadata {
            extensions[kCMFormatDescriptionExtension_ContentLightLevelInfo as String] = Data(
                [0x03, 0xE8, 0x01, 0x90]
            )
        }

        var description: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: codec,
            width: width,
            height: height,
            extensions: extensions as CFDictionary,
            formatDescriptionOut: &description
        )
        #expect(status == noErr)
        return try #require(description)
    }

    private func makeAudioDescription(
        formatID: AudioFormatID,
        channelCount: UInt32,
        layoutTag: AudioChannelLayoutTag? = nil,
        sampleRate: Double = 48_000
    ) throws -> CMAudioFormatDescription {
        var streamDescription = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: formatID,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 1_536,
            mBytesPerFrame: 0,
            mChannelsPerFrame: channelCount,
            mBitsPerChannel: 0,
            mReserved: 0
        )
        var channelLayout = AudioChannelLayout()
        channelLayout.mChannelLayoutTag = layoutTag ?? kAudioChannelLayoutTag_Unknown
        channelLayout.mChannelBitmap = AudioChannelBitmap(rawValue: 0)
        channelLayout.mNumberChannelDescriptions = 0
        var description: CMAudioFormatDescription?
        let status = withUnsafePointer(to: &channelLayout) { layoutPointer in
            CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                asbd: &streamDescription,
                layoutSize: layoutTag == nil ? 0 : MemoryLayout<AudioChannelLayout>.size,
                layout: layoutTag == nil ? nil : layoutPointer,
                magicCookieSize: 0,
                magicCookie: nil,
                extensions: nil,
                formatDescriptionOut: &description
            )
        }
        #expect(status == noErr)
        return try #require(description)
    }
}
