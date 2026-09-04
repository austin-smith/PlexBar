import Foundation

enum PlexDownloadVideoQuality: String, CaseIterable, Identifiable, Sendable {
    case original
    case fourK20Mbps
    case fullHD12Mbps
    case fullHD8Mbps
    case hd4Mbps
    case hd2Mbps
    case sd1500Kbps

    var id: Self { self }

    var label: String {
        switch self {
        case .original: "Original"
        case .fourK20Mbps: "4K · 20 Mbps"
        case .fullHD12Mbps: "1080p · 12 Mbps"
        case .fullHD8Mbps: "1080p · 8 Mbps"
        case .hd4Mbps: "720p · 4 Mbps"
        case .hd2Mbps: "720p · 2 Mbps"
        case .sd1500Kbps: "480p · 1.5 Mbps"
        }
    }

    fileprivate var constraints: PlexDownloadVideoQualityConstraints? {
        switch self {
        case .original:
            nil
        case .fourK20Mbps:
            PlexDownloadVideoQualityConstraints(width: 3_840, height: 2_160, bitrate: 20_000)
        case .fullHD12Mbps:
            PlexDownloadVideoQualityConstraints(width: 1_920, height: 1_080, bitrate: 12_000)
        case .fullHD8Mbps:
            PlexDownloadVideoQualityConstraints(width: 1_920, height: 1_080, bitrate: 8_000)
        case .hd4Mbps:
            PlexDownloadVideoQualityConstraints(width: 1_280, height: 720, bitrate: 4_000)
        case .hd2Mbps:
            PlexDownloadVideoQualityConstraints(width: 1_280, height: 720, bitrate: 2_000)
        case .sd1500Kbps:
            PlexDownloadVideoQualityConstraints(width: 854, height: 480, bitrate: 1_500)
        }
    }
}

enum PlexDownloadMusicQuality: String, CaseIterable, Identifiable, Sendable {
    case original
    case kbps320
    case kbps256
    case kbps192
    case kbps128

    var id: Self { self }

    var label: String {
        switch self {
        case .original: "Original"
        case .kbps320: "320 kbps"
        case .kbps256: "256 kbps"
        case .kbps192: "192 kbps"
        case .kbps128: "128 kbps"
        }
    }

    fileprivate var bitrate: Int? {
        switch self {
        case .original: nil
        case .kbps320: 320
        case .kbps256: 256
        case .kbps192: 192
        case .kbps128: 128
        }
    }
}

enum PlexDownloadSubtitlePreference: String, CaseIterable, Identifiable, Sendable {
    case selectable
    case burn
    case none

    var id: Self { self }

    var label: String {
        switch self {
        case .selectable: "Selectable Track"
        case .burn: "Burn Into Video"
        case .none: "None"
        }
    }

    fileprivate var decisionModes: (
        subtitle: PlexDownloadSubtitleMode,
        advanced: PlexDownloadAdvancedSubtitleMode?
    ) {
        switch self {
        case .selectable:
            (.embedded, .text)
        case .burn:
            (.burn, .burn)
        case .none:
            (.none, nil)
        }
    }
}

struct PlexDownloadPreferences: Equatable, Sendable {
    static let `default` = Self(
        videoQuality: .original,
        musicQuality: .original,
        subtitlePreference: .selectable
    )

    let videoQuality: PlexDownloadVideoQuality
    let musicQuality: PlexDownloadMusicQuality
    let subtitlePreference: PlexDownloadSubtitlePreference

    func decisionParameters(
        for item: PlexMediaItem,
        source: PlexPlaybackSource,
        sessionIdentifier: String,
        nativeDirectPlaySupported: Bool = true,
        clientProfileName: String? = nil,
        clientProfileExtra: String? = nil
    ) throws -> PlexDownloadDecisionParameters {
        guard item.media.indices.contains(source.mediaIndex),
              let sessionIdentifier = sessionIdentifier.nilIfBlank else {
            throw PlexDownloadPreferencesError.invalidMediaSource
        }

        let media = item.media[source.mediaIndex]
        let hasValidPartSelection = if source.partIndex == -1 {
            media.parts.count > 1
        } else {
            media.parts.indices.contains(source.partIndex)
        }
        guard hasValidPartSelection else {
            throw PlexDownloadPreferencesError.invalidMediaSource
        }

        let mediaPath = item.key?.nilIfBlank ?? "/library/metadata/\(item.ratingKey)"
        if media.videoCodec?.nilIfBlank != nil {
            return videoDecisionParameters(
                media: media,
                mediaPath: mediaPath,
                source: source,
                sessionIdentifier: sessionIdentifier,
                nativeDirectPlaySupported: nativeDirectPlaySupported,
                clientProfileName: clientProfileName,
                clientProfileExtra: clientProfileExtra
            )
        }
        if media.audioCodec?.nilIfBlank != nil {
            return musicDecisionParameters(
                media: media,
                mediaPath: mediaPath,
                source: source,
                sessionIdentifier: sessionIdentifier,
                nativeDirectPlaySupported: nativeDirectPlaySupported,
                clientProfileName: clientProfileName,
                clientProfileExtra: clientProfileExtra
            )
        }
        throw PlexDownloadPreferencesError.unsupportedMedia
    }

    private func videoDecisionParameters(
        media: PlexMediaVersion,
        mediaPath: String,
        source: PlexPlaybackSource,
        sessionIdentifier: String,
        nativeDirectPlaySupported: Bool,
        clientProfileName: String?,
        clientProfileExtra: String?
    ) -> PlexDownloadDecisionParameters {
        let limitsSource = videoQuality.limits(media: media)
        let joinsMultipleParts = source.partIndex == -1
        let requiresServerConversion = limitsSource || joinsMultipleParts
        let constraints = videoQuality.constraints
        let resolution = constraints.map { "\($0.width)x\($0.height)" }
            ?? media.sourceResolution
        let subtitleModes = subtitlePreference.decisionModes

        return PlexDownloadDecisionParameters(
            mediaPath: mediaPath,
            mediaIndex: source.mediaIndex,
            partIndex: source.partIndex,
            deliveryProtocol: .http,
            allowsDirectPlay: !requiresServerConversion && nativeDirectPlaySupported,
            allowsDirectStream: !requiresServerConversion,
            allowsDirectStreamAudio: !joinsMultipleParts,
            subtitleMode: subtitleModes.subtitle,
            advancedSubtitleMode: subtitleModes.advanced,
            videoBitrate: constraints?.bitrate ?? media.positiveBitrate,
            videoQuality: 99,
            videoResolution: resolution,
            sessionIdentifier: sessionIdentifier,
            clientProfileName: clientProfileName,
            clientProfileExtra: clientProfileExtra
        )
    }

    private func musicDecisionParameters(
        media: PlexMediaVersion,
        mediaPath: String,
        source: PlexPlaybackSource,
        sessionIdentifier: String,
        nativeDirectPlaySupported: Bool,
        clientProfileName: String?,
        clientProfileExtra: String?
    ) -> PlexDownloadDecisionParameters {
        let targetBitrate = musicQuality.bitrate ?? media.positiveBitrate
        let limitsSource = musicQuality.limits(media: media)
        let joinsMultipleParts = source.partIndex == -1
        let requiresServerConversion = limitsSource || joinsMultipleParts
        return PlexDownloadDecisionParameters(
            mediaPath: mediaPath,
            mediaIndex: source.mediaIndex,
            partIndex: source.partIndex,
            deliveryProtocol: .http,
            allowsDirectPlay: !requiresServerConversion && nativeDirectPlaySupported,
            allowsDirectStreamAudio: !requiresServerConversion,
            musicBitrate: targetBitrate,
            sessionIdentifier: sessionIdentifier,
            clientProfileName: clientProfileName,
            clientProfileExtra: clientProfileExtra
        )
    }
}

enum PlexDownloadPreferencesError: LocalizedError, Equatable {
    case invalidMediaSource
    case unsupportedMedia

    var errorDescription: String? {
        switch self {
        case .invalidMediaSource:
            "Plex did not provide a valid media source for this download."
        case .unsupportedMedia:
            "This Plex item does not contain downloadable video or music."
        }
    }
}

private struct PlexDownloadVideoQualityConstraints: Equatable, Sendable {
    let width: Int
    let height: Int
    let bitrate: Int
}

private extension PlexDownloadVideoQuality {
    func limits(media: PlexMediaVersion) -> Bool {
        guard let constraints else {
            return false
        }
        guard let width = media.width, width > 0,
              let height = media.height, height > 0,
              let bitrate = media.positiveBitrate else {
            return true
        }
        return width > constraints.width
            || height > constraints.height
            || bitrate > constraints.bitrate
    }
}

private extension PlexDownloadMusicQuality {
    func limits(media: PlexMediaVersion) -> Bool {
        guard let bitrate else {
            return false
        }
        guard let sourceBitrate = media.positiveBitrate else {
            return true
        }
        return sourceBitrate > bitrate
    }
}

private extension PlexMediaVersion {
    var positiveBitrate: Int? {
        guard let bitrate, bitrate > 0 else {
            return nil
        }
        return bitrate
    }

    var sourceResolution: String? {
        guard let width, width > 0, let height, height > 0 else {
            return nil
        }
        return "\(width)x\(height)"
    }
}
