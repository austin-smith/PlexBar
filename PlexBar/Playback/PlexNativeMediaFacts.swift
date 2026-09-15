import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation

enum PlexVideoDynamicRange: String, Equatable, Sendable {
    case dolbyVision = "Dolby Vision"
    case hdr10 = "HDR10"
    case hdrPQ = "HDR (PQ)"
    case hlg = "HLG"
    case sdr = "SDR"
}

enum PlexDeliveredAudioLayout: String, Equatable, Sendable {
    case surround5_1 = "5.1"
    case surround6_1 = "6.1"
    case surround7_1 = "7.1"
    case atmos5_1_2 = "Atmos 5.1.2"
    case atmos5_1_4 = "Atmos 5.1.4"
    case atmos7_1_2 = "Atmos 7.1.2"
    case atmos7_1_4 = "Atmos 7.1.4"
    case atmos9_1_6 = "Atmos 9.1.6"
}

struct PlexNativeMediaDiagnosticFact: Equatable, Identifiable, Sendable {
    enum Kind: String, Sendable {
        case resolution
        case frameRate
        case videoCodec
        case dynamicRange
        case videoBitRate
        case audioCodec
        case channels
        case sampleRate
        case audioBitRate
    }

    let kind: Kind
    let label: String
    let value: String

    var id: Kind { kind }
}

struct PlexNativeMediaFacts: Equatable, Sendable {
    let videoWidth: Int?
    let videoHeight: Int?
    let videoFrameRate: Double?
    let videoCodec: String?
    let dynamicRange: PlexVideoDynamicRange?
    let videoBitRate: Double?
    let audioCodec: String?
    let audioChannelCount: Int?
    let audioLayout: PlexDeliveredAudioLayout?
    let audioSampleRate: Double?
    let audioBitRate: Double?

    var compactDisplayComponents: [String] {
        var components: [String] = []

        if let videoWidth, let videoHeight {
            components.append("\(videoWidth) × \(videoHeight)")
        }
        if let videoCodec {
            components.append(videoCodec)
        }
        if let dynamicRange {
            components.append(dynamicRange.rawValue)
        }
        if let audioCodec {
            components.append(
                [audioCodec, audioLayoutLabel].compactMap { $0 }.joined(separator: " ")
            )
        } else if let audioLayoutLabel {
            components.append(audioLayoutLabel)
        }

        return components
    }

    var diagnosticFacts: [PlexNativeMediaDiagnosticFact] {
        var facts: [PlexNativeMediaDiagnosticFact] = []

        if let videoWidth, let videoHeight {
            facts.append(.init(
                kind: .resolution,
                label: "Resolution",
                value: "\(videoWidth) × \(videoHeight)"
            ))
        }
        if let videoFrameRateLabel {
            facts.append(.init(kind: .frameRate, label: "Frame Rate", value: videoFrameRateLabel))
        }
        if let videoCodec {
            facts.append(.init(kind: .videoCodec, label: "Video Codec", value: videoCodec))
        }
        if let dynamicRange {
            facts.append(.init(
                kind: .dynamicRange,
                label: "Dynamic Range",
                value: dynamicRange.rawValue
            ))
        }
        if let videoBitRateValue {
            facts.append(.init(
                kind: .videoBitRate,
                label: "Video Data Rate",
                value: videoBitRateValue
            ))
        }
        if let audioCodec {
            facts.append(.init(kind: .audioCodec, label: "Audio Codec", value: audioCodec))
        }
        if let audioLayoutLabel {
            facts.append(.init(kind: .channels, label: "Channels", value: audioLayoutLabel))
        }
        if let audioSampleRateLabel {
            facts.append(.init(
                kind: .sampleRate,
                label: "Sample Rate",
                value: audioSampleRateLabel
            ))
        }
        if let audioBitRateValue {
            facts.append(.init(
                kind: .audioBitRate,
                label: "Audio Data Rate",
                value: audioBitRateValue
            ))
        }

        return facts
    }

    var videoDiagnosticFacts: [PlexNativeMediaDiagnosticFact] {
        diagnosticFacts.filter { fact in
            switch fact.kind {
            case .resolution, .frameRate, .videoCodec, .dynamicRange, .videoBitRate:
                true
            case .audioCodec, .channels, .sampleRate, .audioBitRate:
                false
            }
        }
    }

    var audioDiagnosticFacts: [PlexNativeMediaDiagnosticFact] {
        diagnosticFacts.filter { fact in
            switch fact.kind {
            case .audioCodec, .channels, .sampleRate, .audioBitRate:
                true
            case .resolution, .frameRate, .videoCodec, .dynamicRange, .videoBitRate:
                false
            }
        }
    }

    var displayComponents: [String] {
        var components: [String] = []

        if let videoWidth, let videoHeight {
            components.append("\(videoWidth) × \(videoHeight)")
        }
        if let videoFrameRateLabel {
            components.append(videoFrameRateLabel)
        }
        if let videoCodec {
            components.append(videoCodec)
        }
        if let dynamicRange {
            components.append(dynamicRange.rawValue)
        }
        if let videoBitRateLabel {
            components.append(videoBitRateLabel)
        }
        if let audioCodec {
            components.append(
                [audioCodec, audioLayoutLabel].compactMap { $0 }.joined(separator: " ")
            )
        } else if let audioLayoutLabel {
            components.append(audioLayoutLabel)
        }
        if let audioSampleRateLabel {
            components.append(audioSampleRateLabel)
        }
        if let audioBitRateLabel {
            components.append(audioBitRateLabel)
        }

        return components
    }

    private var videoFrameRateLabel: String? {
        guard let videoFrameRate = Self.positiveFinite(videoFrameRate) else {
            return nil
        }
        return "\(Self.formatted(videoFrameRate, maximumFractionDigits: 3)) fps"
    }

    private var videoBitRateLabel: String? {
        videoBitRateValue.map { "\($0) video" }
    }

    private var videoBitRateValue: String? {
        Self.bitRateValue(videoBitRate)
    }

    private var audioLayoutLabel: String? {
        if let audioLayout {
            return audioLayout.rawValue
        }
        guard let audioChannelCount, audioChannelCount > 0 else {
            return nil
        }

        return switch audioChannelCount {
        case 1: "Mono"
        case 2: "Stereo"
        default: "\(audioChannelCount) ch"
        }
    }

    private var audioSampleRateLabel: String? {
        guard let audioSampleRate = Self.positiveFinite(audioSampleRate) else {
            return nil
        }
        if audioSampleRate >= 1_000 {
            let sampleRate = Self.formatted(
                audioSampleRate / 1_000,
                maximumFractionDigits: 3
            )
            return "\(sampleRate) kHz"
        }
        return "\(Self.formatted(audioSampleRate, maximumFractionDigits: 0)) Hz"
    }

    private var audioBitRateLabel: String? {
        audioBitRateValue.map { "\($0) audio" }
    }

    private var audioBitRateValue: String? {
        Self.bitRateValue(audioBitRate)
    }

    private static func bitRateValue(_ bitsPerSecond: Double?) -> String? {
        guard let bitsPerSecond = positiveFinite(bitsPerSecond) else {
            return nil
        }
        if bitsPerSecond >= 1_000_000 {
            let bitRate = formatted(
                bitsPerSecond / 1_000_000,
                maximumFractionDigits: 3
            )
            return "\(bitRate) Mbps"
        }
        if bitsPerSecond >= 1_000 {
            let bitRate = formatted(
                bitsPerSecond / 1_000,
                maximumFractionDigits: 3
            )
            return "\(bitRate) kbps"
        }
        return "\(formatted(bitsPerSecond, maximumFractionDigits: 0)) bps"
    }

    private static func positiveFinite(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else {
            return nil
        }
        return value
    }

    private static func formatted(_ value: Double, maximumFractionDigits: Int) -> String {
        value.formatted(
            .number
                .locale(Locale(identifier: "en_US_POSIX"))
                .precision(.fractionLength(0...maximumFractionDigits))
        )
    }
}

enum PlexNativeMediaInspector {
    @MainActor
    static func mediaSelectionAvailability(
        asset: AVAsset
    ) async throws -> PlexNativeMediaSelectionAvailability {
        let audioGroup = try await asset.loadMediaSelectionGroup(for: .audible)
        let subtitleGroup = try await asset.loadMediaSelectionGroup(for: .legible)
        return PlexNativeMediaSelectionAvailability(
            audioOptionCount: audioGroup?.options.count ?? 0,
            subtitleOptionCount: subtitleGroup?.options.count ?? 0
        )
    }

    @MainActor
    static func inspect(item: AVPlayerItem) async -> PlexNativeMediaFacts? {
        var videoDescription: CMFormatDescription?
        var audioDescription: CMFormatDescription?
        var videoTrack: AVAssetTrack?
        var audioTrack: AVAssetTrack?

        for itemTrack in item.tracks where itemTrack.isEnabled {
            guard let assetTrack = itemTrack.assetTrack,
                  let descriptions = try? await assetTrack.load(.formatDescriptions) else {
                continue
            }

            for description in descriptions {
                switch CMFormatDescriptionGetMediaType(description) {
                case kCMMediaType_Video where videoDescription == nil:
                    videoDescription = description
                    videoTrack = assetTrack
                case kCMMediaType_Audio where audioDescription == nil:
                    audioDescription = description
                    audioTrack = assetTrack
                default:
                    break
                }
            }
        }

        var videoFrameRate: Float?
        var videoBitRate: Float?
        if let videoTrack {
            videoFrameRate = try? await videoTrack.load(.nominalFrameRate)
            videoBitRate = try? await videoTrack.load(.estimatedDataRate)
        }
        var audioBitRate: Float?
        if let audioTrack {
            audioBitRate = try? await audioTrack.load(.estimatedDataRate)
        }

        return facts(
            videoFormatDescription: videoDescription,
            audioFormatDescription: audioDescription,
            videoFrameRate: videoFrameRate.map(Double.init),
            videoBitRate: videoBitRate.map(Double.init),
            audioBitRate: audioBitRate.map(Double.init)
        )
    }

    static func facts(
        videoFormatDescription: CMFormatDescription?,
        audioFormatDescription: CMFormatDescription?,
        videoFrameRate: Double? = nil,
        videoBitRate: Double? = nil,
        audioBitRate: Double? = nil
    ) -> PlexNativeMediaFacts? {
        let videoSubtype = videoFormatDescription.map(CMFormatDescriptionGetMediaSubType)
        let dimensions = videoFormatDescription.map(CMVideoFormatDescriptionGetDimensions)
        let audioStreamDescription = audioFormatDescription.flatMap {
            CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee
        }
        let audioFormatID = audioStreamDescription?.mFormatID
            ?? audioFormatDescription.map(CMFormatDescriptionGetMediaSubType)
        let audioLayoutTag = audioFormatDescription.flatMap {
            CMAudioFormatDescriptionGetChannelLayout($0, sizeOut: nil)?.pointee.mChannelLayoutTag
        }

        let facts = PlexNativeMediaFacts(
            videoWidth: positiveInt(dimensions?.width),
            videoHeight: positiveInt(dimensions?.height),
            videoFrameRate: positiveFinite(videoFrameRate),
            videoCodec: videoSubtype.flatMap(videoCodecName),
            dynamicRange: videoFormatDescription.flatMap(dynamicRange),
            videoBitRate: positiveFinite(videoBitRate),
            audioCodec: audioFormatID.flatMap(audioCodecName),
            audioChannelCount: positiveInt(audioStreamDescription?.mChannelsPerFrame),
            audioLayout: audioLayoutTag.flatMap(audioLayout),
            audioSampleRate: positiveFinite(audioStreamDescription?.mSampleRate),
            audioBitRate: positiveFinite(audioBitRate)
        )

        return facts.displayComponents.isEmpty ? nil : facts
    }

    static func videoCodecName(for mediaSubtype: FourCharCode) -> String? {
        switch mediaSubtype {
        case kCMVideoCodecType_H264, fourCC("avc3"), fourCC("dva1"), fourCC("dvav"):
            "H.264"
        case kCMVideoCodecType_HEVC,
             kCMVideoCodecType_HEVCWithAlpha,
             kCMVideoCodecType_DolbyVisionHEVC,
             fourCC("hev1"),
             fourCC("dvhe"):
            "HEVC"
        case kCMVideoCodecType_AV1:
            "AV1"
        case kCMVideoCodecType_VP9:
            "VP9"
        case kCMVideoCodecType_MPEG4Video:
            "MPEG-4 Video"
        case kCMVideoCodecType_AppleProRes4444XQ,
             kCMVideoCodecType_AppleProRes4444,
             kCMVideoCodecType_AppleProRes422HQ,
             kCMVideoCodecType_AppleProRes422,
             kCMVideoCodecType_AppleProRes422LT,
             kCMVideoCodecType_AppleProRes422Proxy:
            "Apple ProRes"
        default:
            nil
        }
    }

    static func audioCodecName(for formatID: AudioFormatID) -> String? {
        switch formatID {
        case kAudioFormatMPEG4AAC,
             kAudioFormatMPEG4AAC_HE,
             kAudioFormatMPEG4AAC_HE_V2,
             kAudioFormatMPEG4AAC_LD,
             kAudioFormatMPEG4AAC_ELD,
             kAudioFormatMPEG4AAC_ELD_SBR,
             kAudioFormatMPEG4AAC_ELD_V2,
             kAudioFormatMPEG4AAC_Spatial,
             fourCC("mp4a"):
            "AAC"
        case kAudioFormatAC3:
            "AC-3"
        case kAudioFormatEnhancedAC3:
            "E-AC-3"
        case kAudioFormatAppleLossless:
            "ALAC"
        case kAudioFormatFLAC:
            "FLAC"
        case kAudioFormatOpus:
            "Opus"
        case kAudioFormatMPEGLayer3:
            "MP3"
        case kAudioFormatLinearPCM:
            "PCM"
        default:
            nil
        }
    }

    static func audioLayout(for tag: AudioChannelLayoutTag) -> PlexDeliveredAudioLayout? {
        switch tag {
        case kAudioChannelLayoutTag_MPEG_5_1_A,
             kAudioChannelLayoutTag_MPEG_5_1_B,
             kAudioChannelLayoutTag_MPEG_5_1_C,
             kAudioChannelLayoutTag_MPEG_5_1_D,
             kAudioChannelLayoutTag_MPEG_5_1_E,
             kAudioChannelLayoutTag_WAVE_5_1_B:
            .surround5_1
        case kAudioChannelLayoutTag_MPEG_6_1_A,
             kAudioChannelLayoutTag_MPEG_6_1_B,
             kAudioChannelLayoutTag_AAC_6_1,
             kAudioChannelLayoutTag_EAC3_6_1_A,
             kAudioChannelLayoutTag_EAC3_6_1_B,
             kAudioChannelLayoutTag_EAC3_6_1_C,
             kAudioChannelLayoutTag_DTS_6_1_A,
             kAudioChannelLayoutTag_DTS_6_1_B,
             kAudioChannelLayoutTag_DTS_6_1_C,
             kAudioChannelLayoutTag_DTS_6_1_D,
             kAudioChannelLayoutTag_WAVE_6_1:
            .surround6_1
        case kAudioChannelLayoutTag_MPEG_7_1_A,
             kAudioChannelLayoutTag_MPEG_7_1_B,
             kAudioChannelLayoutTag_MPEG_7_1_C,
             kAudioChannelLayoutTag_MPEG_7_1_D,
             kAudioChannelLayoutTag_AAC_7_1_B,
             kAudioChannelLayoutTag_AAC_7_1_C,
             kAudioChannelLayoutTag_EAC3_7_1_A,
             kAudioChannelLayoutTag_EAC3_7_1_B,
             kAudioChannelLayoutTag_EAC3_7_1_C,
             kAudioChannelLayoutTag_EAC3_7_1_D,
             kAudioChannelLayoutTag_EAC3_7_1_E,
             kAudioChannelLayoutTag_EAC3_7_1_F,
             kAudioChannelLayoutTag_EAC3_7_1_G,
             kAudioChannelLayoutTag_EAC3_7_1_H,
             kAudioChannelLayoutTag_DTS_7_1,
             kAudioChannelLayoutTag_WAVE_7_1:
            .surround7_1
        case kAudioChannelLayoutTag_Atmos_5_1_2:
            .atmos5_1_2
        case kAudioChannelLayoutTag_Atmos_5_1_4:
            .atmos5_1_4
        case kAudioChannelLayoutTag_Atmos_7_1_2:
            .atmos7_1_2
        case kAudioChannelLayoutTag_Atmos_7_1_4:
            .atmos7_1_4
        case kAudioChannelLayoutTag_Atmos_9_1_6:
            .atmos9_1_6
        default:
            nil
        }
    }

    static func dynamicRange(
        mediaSubtype: FourCharCode,
        transferFunction: CFString?,
        hasHDR10StaticMetadata: Bool
    ) -> PlexVideoDynamicRange? {
        if [
            kCMVideoCodecType_DolbyVisionHEVC,
            fourCC("dvhe"),
            fourCC("dva1"),
            fourCC("dvav"),
        ].contains(mediaSubtype) {
            return .dolbyVision
        }

        guard let transferFunction else {
            return nil
        }

        if CFEqual(transferFunction, kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ) {
            return hasHDR10StaticMetadata ? .hdr10 : .hdrPQ
        }
        if CFEqual(transferFunction, kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG) {
            return .hlg
        }
        if CFEqual(transferFunction, kCMFormatDescriptionTransferFunction_ITU_R_709_2)
            || CFEqual(transferFunction, kCMFormatDescriptionTransferFunction_ITU_R_2020)
            || CFEqual(transferFunction, kCMFormatDescriptionTransferFunction_sRGB) {
            return .sdr
        }

        return nil
    }

    private static func dynamicRange(
        for description: CMFormatDescription
    ) -> PlexVideoDynamicRange? {
        let subtype = CMFormatDescriptionGetMediaSubType(description)
        let transferFunction: CFString?
        if let value = CMFormatDescriptionGetExtension(
            description,
            extensionKey: kCMFormatDescriptionExtension_TransferFunction
        ), CFGetTypeID(value) == CFStringGetTypeID() {
            transferFunction = (value as! CFString)
        } else {
            transferFunction = nil
        }
        let hasHDR10StaticMetadata = CMFormatDescriptionGetExtension(
            description,
            extensionKey: kCMFormatDescriptionExtension_MasteringDisplayColorVolume
        ) != nil || CMFormatDescriptionGetExtension(
            description,
            extensionKey: kCMFormatDescriptionExtension_ContentLightLevelInfo
        ) != nil

        return dynamicRange(
            mediaSubtype: subtype,
            transferFunction: transferFunction,
            hasHDR10StaticMetadata: hasHDR10StaticMetadata
        )
    }

    private static func positiveInt<T: BinaryInteger>(_ value: T?) -> Int? {
        guard let value, value > 0 else {
            return nil
        }
        return Int(value)
    }

    private static func positiveFinite(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else {
            return nil
        }
        return value
    }

    private static func fourCC(_ string: StaticString) -> FourCharCode {
        let bytes = string.withUTF8Buffer { Array($0) }
        precondition(bytes.count == 4)
        return bytes.reduce(0) { partialResult, byte in
            (partialResult << 8) | FourCharCode(byte)
        }
    }
}
