import Foundation

enum PlexPlaybackMediaKind: String, Equatable, Sendable {
    case video
    case music

    init(media: PlexMediaVersion) {
        self = media.videoCodec?.nilIfBlank == nil
            && media.audioCodec?.nilIfBlank != nil
            ? .music
            : .video
    }

    var decisionPath: String {
        "/\(rawValue)/:/transcode/universal/decision"
    }

    var startPath: String {
        "/\(rawValue)/:/transcode/universal/start.m3u8"
    }
}

enum PlexVideoDisplayDynamicRange: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case standard
    case constrainedHigh
    case high

    var id: Self { self }

    var label: String {
        switch self {
        case .automatic: "Automatic"
        case .standard: "Standard Dynamic Range"
        case .constrainedHigh: "Constrained High Dynamic Range"
        case .high: "High Dynamic Range"
        }
    }
}

enum PlexVideoScalingMode: String, CaseIterable, Identifiable, Sendable {
    case fit
    case fill

    var id: Self { self }

    var label: String {
        switch self {
        case .fit: "Fit"
        case .fill: "Fill"
        }
    }
}

struct PlexPlaybackStreamingPolicy: Equatable, Sendable {
    static let automatic = Self(
        allowsDirectPlay: true,
        allowsDirectStream: true,
        forceDirectPlay: false
    )

    let allowsDirectPlay: Bool
    let allowsDirectStream: Bool
    let forceDirectPlay: Bool

    init(
        allowsDirectPlay: Bool,
        allowsDirectStream: Bool,
        forceDirectPlay: Bool = false
    ) {
        self.allowsDirectPlay = allowsDirectPlay
        self.allowsDirectStream = allowsDirectStream
        self.forceDirectPlay = forceDirectPlay
    }
}

struct PlexMusicDirectPlayProfile: Hashable, Sendable {
    let container: String
    let audioCodec: String
}

struct PlexPlaybackCapabilities: Equatable, Sendable {
    let directPlayContainers: Set<String>
    let directPlayVideoCodecs: Set<String>
    let directPlayAudioCodecs: Set<String>
    let directPlayMusicProfiles: Set<PlexMusicDirectPlayProfile>

    init(
        directPlayContainers: Set<String>,
        directPlayVideoCodecs: Set<String>,
        directPlayAudioCodecs: Set<String>,
        directPlayMusicProfiles: Set<PlexMusicDirectPlayProfile> = []
    ) {
        self.directPlayContainers = directPlayContainers
        self.directPlayVideoCodecs = directPlayVideoCodecs
        self.directPlayAudioCodecs = directPlayAudioCodecs
        self.directPlayMusicProfiles = directPlayMusicProfiles
    }

    func clientProfileExtra(for mediaKind: PlexPlaybackMediaKind) -> String {
        switch mediaKind {
        case .video:
            videoClientProfileExtra
        case .music:
            musicClientProfileExtra
        }
    }

    func downloadClientProfileExtra(for mediaKind: PlexPlaybackMediaKind) -> String {
        switch mediaKind {
        case .video:
            let transcodeTarget =
                "add-transcode-target(type=videoProfile&context=static&protocol=http" +
                "&container=mp4&videoCodec=h264&audioCodec=aac" +
                "&subtitleCodec=mov_text&replace=true)"
            return [videoDirectPlayProfile, transcodeTarget]
                .compactMap { $0 }
                .joined(separator: "+")
        case .music:
            let transcodeTarget =
                "add-transcode-target(type=musicProfile&context=static&protocol=http" +
                "&container=mp4&audioCodec=aac&replace=true)"
            return musicDirectPlayProfiles
                .appending(transcodeTarget)
                .joined(separator: "+")
        }
    }

    /// Returns an exact PMS media-part path only when the selected source is a
    /// single file whose declared container and codecs independently satisfy
    /// this Mac's native AVFoundation and VideoToolbox capability contract.
    /// Missing facts, multipart media, and selected subtitle streams are not
    /// guessed; those sources remain owned by PMS's universal decision path.
    func directPlayPath(
        for item: PlexMediaItem,
        source: PlexPlaybackSource
    ) -> String? {
        guard item.media.indices.contains(source.mediaIndex), source.partIndex >= 0 else {
            return nil
        }

        let media = item.media[source.mediaIndex]
        guard media.parts.indices.contains(source.partIndex) else {
            return nil
        }

        let part = media.parts[source.partIndex]
        guard let path = part.key?.nilIfBlank,
              let container = normalized(part.container ?? media.container) else {
            return nil
        }

        let mediaKind = PlexPlaybackMediaKind(media: media)
        switch mediaKind {
        case .video:
            guard directPlayContainers.contains(container),
                  let videoCodec = normalized(media.videoCodec),
                  directPlayVideoCodecs.contains(videoCodec) else {
                return nil
            }
            if let audioCodec = normalized(media.audioCodec),
               !directPlayAudioCodecs.contains(audioCodec) {
                return nil
            }
        case .music:
            guard let audioCodec = normalized(media.audioCodec),
                  directPlayMusicProfiles.contains(PlexMusicDirectPlayProfile(
                      container: container,
                      audioCodec: audioCodec
                  )) else {
                return nil
            }
        }

        for stream in part.streams where stream.selected == true {
            guard let codec = normalized(stream.codec) else {
                return nil
            }
            switch stream.streamType {
            case 1:
                guard mediaKind == .video,
                      directPlayVideoCodecs.contains(codec) else { return nil }
            case 2:
                switch mediaKind {
                case .video:
                    guard directPlayAudioCodecs.contains(codec) else { return nil }
                case .music:
                    guard codec == normalized(media.audioCodec) else { return nil }
                }
            case 3:
                return nil
            default:
                return nil
            }
        }

        return path
    }

    private func normalized(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .nilIfBlank
    }

    private var videoClientProfileExtra: String {
        let transcodeTarget =
            "add-transcode-target(type=videoProfile&context=streaming&protocol=hls" +
            "&container=mpegts&videoCodec=h264&audioCodec=aac)"
        return [videoDirectPlayProfile, transcodeTarget]
            .compactMap { $0 }
            .joined(separator: "+")
    }

    private var musicClientProfileExtra: String {
        musicDirectPlayProfiles
            .appending(
                "add-transcode-target(type=musicProfile&context=streaming&protocol=hls" +
                "&container=mpegts&audioCodec=aac)"
            )
            .joined(separator: "+")
    }

    private var videoDirectPlayProfile: String? {
        let containers = directPlayContainers.sorted().joined(separator: ",")
        let videoCodecs = directPlayVideoCodecs.sorted().joined(separator: ",")
        let audioCodecs = directPlayAudioCodecs.sorted().joined(separator: ",")
        guard !containers.isEmpty, !videoCodecs.isEmpty, !audioCodecs.isEmpty else {
            return nil
        }
        return "add-direct-play-profile(type=videoProfile&container=\(containers)" +
            "&videoCodec=\(videoCodecs)&audioCodec=\(audioCodecs)&subtitleCodec=*)"
    }

    private var musicDirectPlayProfiles: [String] {
        directPlayMusicProfiles
            .sorted {
                ($0.container, $0.audioCodec) < ($1.container, $1.audioCodec)
            }
            .map { profile in
                "add-direct-play-profile(type=musicProfile&container=\(profile.container)" +
                    "&videoCodec=*&audioCodec=\(profile.audioCodec)&subtitleCodec=*)"
            }
    }
}

private extension Array where Element == String {
    func appending(_ value: String) -> [String] {
        self + [value]
    }
}

struct PlexPlaybackPlan: Equatable, Sendable {
    enum Method: String, Equatable, Sendable {
        case directPlay
        case directStream
        case transcode
    }

    let url: URL
    let method: Method
    let mediaKind: PlexPlaybackMediaKind
    let sessionIdentifier: String
    let ratingKey: String
    let duration: TimeInterval?
    let startTime: TimeInterval
    let source: PlexPlaybackSource
    let usesServerMediaSelection: Bool
}

struct PlexPlaybackSource: Codable, Equatable, Sendable {
    let mediaIndex: Int
    let partIndex: Int
}

struct PlexAudioPlaybackPresentation: Equatable, Sendable {
    let title: String
    let metadataLines: [String]
    let artworkPaths: [String]

    init?(item: PlexMediaItem, source: PlexPlaybackSource) {
        guard item.media.indices.contains(source.mediaIndex) else {
            return nil
        }

        let media = item.media[source.mediaIndex]
        guard PlexPlaybackMediaKind(media: media) == .music else {
            return nil
        }

        title = item.title
        artworkPaths = item.nowPlayingArtworkPaths

        let candidates = [
            item.grandparentTitle?.nilIfBlank ?? item.originalTitle?.nilIfBlank,
            item.parentTitle?.nilIfBlank,
        ]
        var seen = Set([item.title])
        metadataLines = candidates.compactMap { candidate in
            guard let candidate, seen.insert(candidate).inserted else {
                return nil
            }
            return candidate
        }
    }
}

enum PlexPlaybackStartOption: Equatable, Sendable {
    case resume
    case beginning

    var startTimeOverride: TimeInterval? {
        switch self {
        case .resume:
            nil
        case .beginning:
            0
        }
    }
}

enum PlexCinemaPreplayRequestPolicy {
    static func extrasPrefixCount(
        for item: PlexMediaItem,
        startOption: PlexPlaybackStartOption,
        preference: PlexCinemaPreplayPreference
    ) -> Int? {
        guard item.type?.lowercased() == "movie",
              startOption == .beginning else {
            return nil
        }
        return preference.extrasPrefixCount
    }
}

struct PlexPlaybackQueueSourcePreference: Equatable, Sendable {
    let ratingKey: String
    let source: PlexPlaybackSource

    func source(for item: PlexMediaItem) -> PlexPlaybackSource? {
        item.ratingKey == ratingKey ? source : nil
    }
}

enum PlexPlaybackSkipDirection: Sendable {
    case backward
    case forward

    func offset(for interval: TimeInterval) -> TimeInterval? {
        guard interval.isFinite, interval > 0 else {
            return nil
        }
        switch self {
        case .backward:
            return -interval
        case .forward:
            return interval
        }
    }
}

enum PlexPlaybackSeek {
    static let skipInterval: TimeInterval = 10

    static func target(
        from position: TimeInterval,
        duration: TimeInterval?,
        offset: TimeInterval
    ) -> TimeInterval {
        let currentPosition = position.isFinite ? max(position, 0) : 0
        let requestedPosition = offset.isFinite ? currentPosition + offset : currentPosition
        return clamped(requestedPosition, duration: duration)
    }

    static func clamped(
        _ position: TimeInterval,
        duration: TimeInterval?
    ) -> TimeInterval {
        let nonnegativePosition = position.isFinite ? max(position, 0) : 0
        guard let duration, duration.isFinite, duration > 0 else {
            return nonnegativePosition
        }
        return min(nonnegativePosition, duration)
    }
}

struct PlexPlaybackSeekSequence: Sendable {
    struct Request: Equatable, Sendable {
        let target: TimeInterval
        fileprivate let generation: UInt
    }

    private(set) var pendingTarget: TimeInterval?
    private var generation: UInt = 0

    mutating func reserve(
        absoluteTarget: TimeInterval,
        duration: TimeInterval?
    ) -> Request {
        reserve(target: PlexPlaybackSeek.clamped(absoluteTarget, duration: duration))
    }

    mutating func reserve(
        relativeOffset: TimeInterval,
        currentPosition: TimeInterval,
        duration: TimeInterval?
    ) -> Request {
        let target = PlexPlaybackSeek.target(
            from: pendingTarget ?? currentPosition,
            duration: duration,
            offset: relativeOffset
        )
        return reserve(target: target)
    }

    func isCurrent(_ request: Request) -> Bool {
        request.generation == generation
    }

    mutating func finish(_ request: Request) -> Bool {
        guard isCurrent(request) else {
            return false
        }
        pendingTarget = nil
        return true
    }

    mutating func invalidate() {
        generation &+= 1
        pendingTarget = nil
    }

    private mutating func reserve(target: TimeInterval) -> Request {
        generation &+= 1
        pendingTarget = target
        return Request(target: target, generation: generation)
    }
}

struct PlexPlaybackTimeJumpExpectations: Sendable {
    struct Token: Equatable, Sendable {
        fileprivate let generation: UInt
    }

    private struct Entry: Sendable {
        let token: Token
        let target: TimeInterval
    }

    static let maximumRetainedCount = 8
    static let matchingTolerance: TimeInterval = 0.25

    private var generation: UInt = 0
    private var entries: [Entry] = []

    var retainedCount: Int {
        entries.count
    }

    mutating func expect(target: TimeInterval) -> Token? {
        guard target.isFinite, target >= 0 else {
            return nil
        }

        generation &+= 1
        let token = Token(generation: generation)
        entries.append(Entry(token: token, target: target))
        if entries.count > Self.maximumRetainedCount {
            entries.removeFirst(entries.count - Self.maximumRetainedCount)
        }
        return token
    }

    mutating func cancel(_ token: Token?) {
        guard let token else {
            return
        }
        entries.removeAll { $0.token == token }
    }

    mutating func consume(position: TimeInterval) -> Bool {
        guard position.isFinite,
              let index = entries.indices.min(by: {
                  abs(entries[$0].target - position) < abs(entries[$1].target - position)
              }),
              abs(entries[index].target - position) <= Self.matchingTolerance else {
            return false
        }

        entries.remove(at: index)
        return true
    }

    mutating func invalidate() {
        generation &+= 1
        entries.removeAll(keepingCapacity: false)
    }
}

struct PlexPlaybackSessionEpoch: Sendable {
    struct Ticket: Equatable, Sendable {
        fileprivate let generation: UInt
    }

    private(set) var isActive = false
    private var generation: UInt = 0

    mutating func activate() -> Ticket {
        generation &+= 1
        isActive = true
        return Ticket(generation: generation)
    }

    func currentTicket() -> Ticket? {
        guard isActive else {
            return nil
        }
        return Ticket(generation: generation)
    }

    func isCurrent(_ ticket: Ticket) -> Bool {
        isActive && ticket.generation == generation
    }

    mutating func invalidate() {
        generation &+= 1
        isActive = false
    }
}

struct PlexTimelineRequestIdentity: Equatable, Sendable {
    let sessionIdentifier: String
    let ticket: PlexPlaybackSessionEpoch.Ticket

    func isCurrent(
        sessionIdentifier: String,
        epoch: PlexPlaybackSessionEpoch
    ) -> Bool {
        self.sessionIdentifier == sessionIdentifier
            && epoch.isCurrent(ticket)
    }
}

enum PlexPlaybackRate: Float, CaseIterable, Identifiable, Sendable {
    case half = 0.5
    case threeQuarters = 0.75
    case normal = 1
    case oneAndAQuarter = 1.25
    case oneAndAHalf = 1.5
    case oneAndThreeQuarters = 1.75
    case double = 2

    var id: Self { self }

    var label: String {
        switch self {
        case .half: "0.5×"
        case .threeQuarters: "0.75×"
        case .normal: "Normal"
        case .oneAndAQuarter: "1.25×"
        case .oneAndAHalf: "1.5×"
        case .oneAndThreeQuarters: "1.75×"
        case .double: "2×"
        }
    }

    init?(remoteCommandValue: Float) {
        guard let rate = Self.allCases.first(where: {
            abs($0.rawValue - remoteCommandValue) < 0.001
        }) else {
            return nil
        }
        self = rate
    }
}

enum PlexPlaybackRepeatMode: CaseIterable, Identifiable, Sendable {
    case off
    case one
    case all

    var id: Self { self }

    var label: String {
        switch self {
        case .off: "Off"
        case .one: "One"
        case .all: "All"
        }
    }
}

enum PlexPlaybackCompletionAction: Equatable, Sendable {
    case stop
    case replayCurrent
    case advanceNext
    case presentPostPlay(autoAdvanceAfterSeconds: Int?)
    case resetQueue

    static func resolve(
        repeatMode: PlexPlaybackRepeatMode,
        canAdvance: Bool,
        canResetQueue: Bool
    ) -> Self {
        if repeatMode == .one {
            return .replayCurrent
        }
        if canAdvance {
            return .advanceNext
        }
        if repeatMode == .all, canResetQueue {
            return .resetQueue
        }
        return .stop
    }

    static func resolve(
        repeatMode: PlexPlaybackRepeatMode,
        canAdvance: Bool,
        canResetQueue: Bool,
        completedItem: PlexMediaItem,
        mediaKind: PlexPlaybackMediaKind,
        duration: TimeInterval?,
        autoplayPreferences: PlexAutoplayPreferences,
        lastInteractionDate: Date,
        isCinemaPreplayItem: Bool = false,
        now: Date = Date()
    ) -> Self {
        if repeatMode == .one {
            return .replayCurrent
        }
        if isCinemaPreplayItem, canAdvance {
            return .advanceNext
        }

        let queueAction = resolve(
            repeatMode: repeatMode,
            canAdvance: canAdvance,
            canResetQueue: canResetQueue
        )
        guard queueAction == .advanceNext,
              mediaKind == .video,
              completedItem.playlistItemID?.nilIfBlank == nil,
              !(completedItem.type?.lowercased() == "clip"
                  && completedItem.subtype?.lowercased() == "trailer") else {
            return queueAction
        }

        if let duration, duration <= 5 * 60 {
            return .advanceNext
        }

        guard autoplayPreferences.isEnabled else {
            return .presentPostPlay(autoAdvanceAfterSeconds: nil)
        }

        if let passoutInterval = autoplayPreferences.passoutProtection.interval,
           let duration,
           duration > 20 * 60,
           max(now.timeIntervalSince(lastInteractionDate), 0) > passoutInterval {
            return .presentPostPlay(autoAdvanceAfterSeconds: nil)
        }

        let countdownSeconds = autoplayPreferences.countdown.rawValue
        return countdownSeconds == 0
            ? .advanceNext
            : .presentPostPlay(autoAdvanceAfterSeconds: countdownSeconds)
    }
}

struct PlexPlaybackReconfigurationPolicy: Equatable, Sendable {
    let canReload: Bool
    let autoplay: Bool

    init(status: PlexPlaybackStatus) {
        switch status {
        case .preparing, .playing, .buffering:
            canReload = true
            autoplay = true
        case .paused:
            canReload = true
            autoplay = false
        case .idle, .ended, .failed:
            canReload = false
            autoplay = false
        }
    }
}

struct PlexVideoQualitySelection: Equatable, Sendable {
    let selectedQuality: PlexVideoQuality
    let isVideo: Bool
    let canChange: Bool

    func canSelect(_ quality: PlexVideoQuality) -> Bool {
        isVideo && canChange && quality != selectedQuality
    }
}

enum PlexPlaybackRecoveryPolicy {
    static func canRetry(
        status: PlexPlaybackStatus,
        isLoading: Bool,
        isActive: Bool,
        didStop: Bool
    ) -> Bool {
        guard case .failed = status else {
            return false
        }
        return !isLoading && isActive && !didStop
    }
}

struct PlexPlaybackRecoveryRequest: Equatable, Sendable {
    let source: PlexPlaybackSource
    let videoQuality: PlexVideoQuality
    let startTime: TimeInterval
    let forceServerMediaSelection: Bool

    init(
        plan: PlexPlaybackPlan,
        videoQuality: PlexVideoQuality,
        position: TimeInterval
    ) {
        source = plan.source
        self.videoQuality = videoQuality
        startTime = position.isFinite ? max(position, 0) : 0
        forceServerMediaSelection = plan.usesServerMediaSelection
    }
}

enum PlexVideoQuality: String, CaseIterable, Identifiable, Sendable {
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

    var constraints: PlexVideoQualityConstraints? {
        switch self {
        case .original:
            nil
        case .fourK20Mbps:
            PlexVideoQualityConstraints(width: 3_840, height: 2_160, bitrate: 20_000)
        case .fullHD12Mbps:
            PlexVideoQualityConstraints(width: 1_920, height: 1_080, bitrate: 12_000)
        case .fullHD8Mbps:
            PlexVideoQualityConstraints(width: 1_920, height: 1_080, bitrate: 8_000)
        case .hd4Mbps:
            PlexVideoQualityConstraints(width: 1_280, height: 720, bitrate: 4_000)
        case .hd2Mbps:
            PlexVideoQualityConstraints(width: 1_280, height: 720, bitrate: 2_000)
        case .sd1500Kbps:
            PlexVideoQualityConstraints(width: 854, height: 480, bitrate: 1_500)
        }
    }
}

struct PlexVideoQualityConstraints: Equatable, Sendable {
    let width: Int
    let height: Int
    let bitrate: Int
}

extension PlexMediaItem {
    var hasResumePosition: Bool {
        guard let viewOffset else {
            return false
        }
        return viewOffset > 0
    }

    var defaultPlaybackSource: PlexPlaybackSource? {
        guard supportsNativePlayback else {
            return nil
        }

        let selectedMediaIndex = media.firstIndex { version in
            version.selected == true && !version.parts.isEmpty
        }
        let firstPlayableMediaIndex = media.firstIndex { !$0.parts.isEmpty }
        guard let mediaIndex = selectedMediaIndex ?? firstPlayableMediaIndex else {
            return nil
        }

        return playbackSource(mediaIndex: mediaIndex)
    }

    func playbackSource(mediaIndex: Int) -> PlexPlaybackSource? {
        guard supportsNativePlayback,
              media.indices.contains(mediaIndex),
              !media[mediaIndex].parts.isEmpty else {
            return nil
        }

        let parts = media[mediaIndex].parts
        let partIndex: Int
        if parts.count == 1 {
            partIndex = parts.firstIndex { $0.selected == true } ?? 0
        } else {
            partIndex = -1
        }

        return PlexPlaybackSource(mediaIndex: mediaIndex, partIndex: partIndex)
    }
}

enum PlexTimelineState: String, Codable, Sendable {
    case stopped
    case buffering
    case playing
    case paused
}

struct PlexTimelineUpdate: Sendable {
    let ratingKey: String
    let state: PlexTimelineState
    let time: Int
    let duration: Int
    let sessionIdentifier: String
    let playQueueItemID: String?
    let continuing: Bool?
    let offline: Bool

    init(
        ratingKey: String,
        state: PlexTimelineState,
        time: Int,
        duration: Int,
        sessionIdentifier: String,
        playQueueItemID: String? = nil,
        continuing: Bool? = nil,
        offline: Bool = false
    ) {
        self.ratingKey = ratingKey
        self.state = state
        self.time = time
        self.duration = duration
        self.sessionIdentifier = sessionIdentifier
        self.playQueueItemID = playQueueItemID
        self.continuing = continuing
        self.offline = offline
    }
}

struct PlexTimelineResponse: Equatable, Sendable {
    struct Termination: Equatable, Sendable {
        let code: Int
        let text: String?

        var message: String {
            text?.nilIfBlank ?? "Plex Media Server ended playback (code \(code))."
        }
    }

    let termination: Termination?
}

struct PlexTimelineResponseEnvelope: Decodable, Sendable {
    let mediaContainer: PlexTimelineResponseContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexTimelineResponseContainer: Decodable, Sendable {
    let terminationCode: Int?
    let terminationText: String?

    private enum CodingKeys: String, CodingKey {
        case terminationCode
        case terminationText
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        terminationCode = values.decodePlexIntIfPresent(forKey: .terminationCode)
        terminationText = try values.decodeIfPresent(String.self, forKey: .terminationText)
    }

    var response: PlexTimelineResponse {
        PlexTimelineResponse(
            termination: terminationCode.map {
                PlexTimelineResponse.Termination(code: $0, text: terminationText)
            }
        )
    }
}

struct PlexPlaybackDecisionEnvelope: Decodable, Sendable {
    let mediaContainer: PlexPlaybackDecisionContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexPlaybackDecisionContainer: Decodable, Sendable {
    let generalDecisionCode: Int?
    let generalDecisionText: String?
    let metadata: [PlexMediaItem]

    enum CodingKeys: String, CodingKey {
        case generalDecisionCode
        case generalDecisionText
        case metadata = "Metadata"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        generalDecisionCode = try Self.decodeDecisionCode(values, key: .generalDecisionCode)
        generalDecisionText = try values.decodeIfPresent(String.self, forKey: .generalDecisionText)
        metadata = try values.decodeIfPresent([PlexMediaItem].self, forKey: .metadata) ?? []
    }

    private static func decodeDecisionCode(
        _ values: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> Int? {
        if let value = try? values.decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? values.decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }
}
