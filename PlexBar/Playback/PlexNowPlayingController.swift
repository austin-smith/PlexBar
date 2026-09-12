import CoreGraphics
import Foundation
@preconcurrency import MediaPlayer

#if os(macOS)
import AppKit
#elseif os(tvOS)
import UIKit
#endif

#if os(macOS)
struct PlexNowPlayingArtworkRequest: Hashable, Sendable {
    static let maximumPixelSize = 1_200

    let candidateURLs: [URL]
    let token: String
    let clientContext: PlexClientContext

    init?(
        item: PlexMediaItem,
        serverURL: URL?,
        token: String,
        clientContext: PlexClientContext
    ) {
        guard let serverURL else {
            return nil
        }
        let candidateURLs = item.nowPlayingArtworkPaths.compactMap {
            PlexURLBuilder.mediaURL(serverURL: serverURL, path: $0)
        }
        guard !candidateURLs.isEmpty else {
            return nil
        }

        self.candidateURLs = candidateURLs
        self.token = token
        self.clientContext = clientContext
    }
}

@MainActor
final class PlexNowPlayingArtworkLoader {
    typealias FetchImage = @Sendable (PlexNowPlayingArtworkRequest) async -> PlexCGImageBox?

    private let fetchImage: FetchImage
    private var loadGeneration = 0

    init(imageClient: PlexImageClient = PlexImageClient()) {
        fetchImage = { request in
            await imageClient.fetchCGImageResult(
                from: request.candidateURLs,
                token: request.token,
                clientContext: request.clientContext,
                maximumPixelSize: PlexNowPlayingArtworkRequest.maximumPixelSize
            ).map { PlexCGImageBox($0.image) }
        }
    }

    init(fetchImage: @escaping FetchImage) {
        self.fetchImage = fetchImage
    }

    func load(_ request: PlexNowPlayingArtworkRequest) async -> CGImage? {
        guard !Task.isCancelled else {
            return nil
        }
        loadGeneration &+= 1
        let generation = loadGeneration
        guard let image = await fetchImage(request),
              !Task.isCancelled,
              generation == loadGeneration else {
            return nil
        }
        return image.image
    }

    func invalidate() {
        loadGeneration &+= 1
    }
}
#endif

enum PlexNowPlayingArtworkFactory {
    static func make(from image: CGImage) -> MPMediaItemArtwork {
        let imageBox = PlexNowPlayingArtworkImageBox(image)
        let boundsSize = CGSize(width: image.width, height: image.height)
        return MPMediaItemArtwork(boundsSize: boundsSize) { requestedSize in
#if os(macOS)
            let size = validRequestedSize(requestedSize, boundedBy: boundsSize)
            return NSImage(cgImage: imageBox.image, size: size)
#elseif os(tvOS)
            return UIImage(cgImage: imageBox.image)
#endif
        }
    }

    private static func validRequestedSize(
        _ requestedSize: CGSize,
        boundedBy boundsSize: CGSize
    ) -> CGSize {
        guard requestedSize.width.isFinite,
              requestedSize.height.isFinite,
              requestedSize.width > 0,
              requestedSize.height > 0 else {
            return boundsSize
        }
        return CGSize(
            width: min(requestedSize.width, boundsSize.width),
            height: min(requestedSize.height, boundsSize.height)
        )
    }
}

private final class PlexNowPlayingArtworkImageBox: @unchecked Sendable {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}

enum PlexNowPlayingLanguageSelection: Equatable, Sendable {
    case audio(streamID: Int)
    case subtitle(streamID: Int)

    init?(languageOption: MPNowPlayingInfoLanguageOption) {
        guard let identifier = languageOption.identifier else {
            return nil
        }
        if identifier.hasPrefix(Self.audioPrefix),
           languageOption.languageOptionType == .audible,
           let streamID = Int(identifier.dropFirst(Self.audioPrefix.count)) {
            self = .audio(streamID: streamID)
        } else if identifier.hasPrefix(Self.subtitlePrefix),
                  languageOption.languageOptionType == .legible,
                  let streamID = Int(identifier.dropFirst(Self.subtitlePrefix.count)) {
            self = .subtitle(streamID: streamID)
        } else {
            return nil
        }
    }

    var identifier: String {
        switch self {
        case .audio(let streamID):
            Self.audioPrefix + String(streamID)
        case .subtitle(let streamID):
            Self.subtitlePrefix + String(streamID)
        }
    }

    private static let audioPrefix = "plex-audio-stream:"
    private static let subtitlePrefix = "plex-subtitle-stream:"
}

struct PlexNowPlayingLanguageOptions {
    let groups: [MPNowPlayingInfoLanguageOptionGroup]
    let currentOptions: [MPNowPlayingInfoLanguageOption]
    let hasSelectedSubtitle: Bool

    init() {
        self.init(groups: [], currentOptions: [], hasSelectedSubtitle: false)
    }

    init(
        selection: PlexPlaybackMediaSelection,
        nativeAvailability: PlexNativeMediaSelectionAvailability?
    ) {
        guard let nativeAvailability else {
            self.init()
            return
        }

        var groups: [MPNowPlayingInfoLanguageOptionGroup] = []
        var currentOptions: [MPNowPlayingInfoLanguageOption] = []
        var hasSelectedSubtitle = false

        let serverManagedSelection = PlexServerManagedMediaSelection(
            selection: selection,
            nativeAvailability: nativeAvailability
        )

        if !serverManagedSelection.audioOptions.isEmpty,
           let audioGroup = Self.group(
               options: serverManagedSelection.audioOptions,
               type: .audible,
               requiresMultipleOptions: true,
               allowsEmptySelection: false
           ) {
            groups.append(audioGroup.group)
            if let selected = audioGroup.selected {
                currentOptions.append(selected)
            }
        }

        if !serverManagedSelection.subtitleOptions.isEmpty,
           let subtitleGroup = Self.group(
               options: serverManagedSelection.subtitleOptions,
               type: .legible,
               requiresMultipleOptions: false,
               allowsEmptySelection: true
           ) {
            groups.append(subtitleGroup.group)
            if let selected = subtitleGroup.selected {
                currentOptions.append(selected)
                hasSelectedSubtitle = true
            }
        }

        self.init(
            groups: groups,
            currentOptions: currentOptions,
            hasSelectedSubtitle: hasSelectedSubtitle
        )
    }

    var hasAvailableOptions: Bool {
        !groups.isEmpty
    }

    private static func group(
        options: [PlexMediaSelectionOption],
        type: MPNowPlayingInfoLanguageOptionType,
        requiresMultipleOptions: Bool,
        allowsEmptySelection: Bool
    ) -> (
        group: MPNowPlayingInfoLanguageOptionGroup,
        selected: MPNowPlayingInfoLanguageOption?
    )? {
        let pairs = options.compactMap { option -> (
            source: PlexMediaSelectionOption,
            languageOption: MPNowPlayingInfoLanguageOption
        )? in
            guard let languageTag = option.languageTag else {
                return nil
            }
            let selection: PlexNowPlayingLanguageSelection
            switch type {
            case .audible:
                selection = .audio(streamID: option.id)
            case .legible:
                selection = .subtitle(streamID: option.id)
            @unknown default:
                return nil
            }
            return (
                option,
                MPNowPlayingInfoLanguageOption(
                    type: type,
                    languageTag: languageTag,
                    characteristics: characteristics(for: option, type: type),
                    displayName: option.title,
                    identifier: selection.identifier
                )
            )
        }
        guard !pairs.isEmpty,
              !requiresMultipleOptions || pairs.count > 1 else {
            return nil
        }

        let selected = pairs.first(where: { $0.source.isSelected })?.languageOption
        guard allowsEmptySelection || selected != nil else {
            return nil
        }
        return (
            MPNowPlayingInfoLanguageOptionGroup(
                languageOptions: pairs.map(\.languageOption),
                defaultLanguageOption: selected,
                allowEmptySelection: allowsEmptySelection
            ),
            selected
        )
    }

    private static func characteristics(
        for option: PlexMediaSelectionOption,
        type: MPNowPlayingInfoLanguageOptionType
    ) -> [String] {
        switch type {
        case .audible:
            if option.isVisualImpaired {
                return [MPLanguageOptionCharacteristicDescribesVideo]
            }
            return [MPLanguageOptionCharacteristicIsMainProgramContent]
        case .legible:
            var characteristics = [MPLanguageOptionCharacteristicTranscribesSpokenDialog]
            if option.isForced {
                characteristics.append(MPLanguageOptionCharacteristicContainsOnlyForcedSubtitles)
            }
            if option.isHearingImpaired {
                characteristics.append(MPLanguageOptionCharacteristicDescribesMusicAndSound)
            }
            return characteristics
        @unknown default:
            return []
        }
    }

    private init(
        groups: [MPNowPlayingInfoLanguageOptionGroup],
        currentOptions: [MPNowPlayingInfoLanguageOption],
        hasSelectedSubtitle: Bool
    ) {
        self.groups = groups
        self.currentOptions = currentOptions
        self.hasSelectedSubtitle = hasSelectedSubtitle
    }
}

struct PlexNowPlayingMetadata: Equatable, Sendable {
    struct PublicationFingerprint: Equatable, Sendable {
        let title: String
        let artist: String?
        let albumTitle: String?
        let genre: String?
        let mediaKind: MediaKind
        let duration: TimeInterval?
        let creditsStartTime: TimeInterval?
        let defaultPlaybackRate: Double
        let itemRatingKey: String
        let externalContentIdentifier: String?
        let collectionIdentifier: String?
        let albumTrackNumber: Int?
        let discNumber: Int?
        let queueIndex: Int?
        let queueCount: Int?
    }

    enum MediaKind: Equatable, Sendable {
        case audio
        case movie
        case television
        case video
    }

    let title: String
    let artist: String?
    let albumTitle: String?
    let genre: String?
    let mediaKind: MediaKind
    let duration: TimeInterval?
    let creditsStartTime: TimeInterval?
    let elapsedTime: TimeInterval
    let playbackRate: Double
    let defaultPlaybackRate: Double
    let itemRatingKey: String
    let externalContentIdentifier: String?
    let collectionIdentifier: String?
    let albumTrackNumber: Int?
    let discNumber: Int?
    let queueIndex: Int?
    let queueCount: Int?

    var publicationFingerprint: PublicationFingerprint {
        PublicationFingerprint(
            title: title,
            artist: artist,
            albumTitle: albumTitle,
            genre: genre,
            mediaKind: mediaKind,
            duration: duration,
            creditsStartTime: creditsStartTime,
            defaultPlaybackRate: defaultPlaybackRate,
            itemRatingKey: itemRatingKey,
            externalContentIdentifier: externalContentIdentifier,
            collectionIdentifier: collectionIdentifier,
            albumTrackNumber: albumTrackNumber,
            discNumber: discNumber,
            queueIndex: queueIndex,
            queueCount: queueCount
        )
    }

    init(
        item: PlexMediaItem,
        duration: TimeInterval?,
        elapsedTime: TimeInterval,
        playbackRate: Double,
        defaultPlaybackRate: Double = 1,
        serverIdentifier: String? = nil,
        queuePosition: Int? = nil,
        queueCount: Int? = nil
    ) {
        let presentation = PlexPlayerPlaybackInfoPresentation(item: item)
        title = presentation.title
        artist = item.grandparentTitle?.nilIfBlank ?? item.originalTitle?.nilIfBlank
        albumTitle = item.parentTitle?.nilIfBlank
        genre = presentation.genre
        mediaKind = Self.mediaKind(for: item.type)
        self.duration = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        creditsStartTime = PlexPlaybackMarkerAction.creditsStartTime(
            in: item.markers,
            duration: self.duration
        )
        self.elapsedTime = elapsedTime.isFinite ? max(elapsedTime, 0) : 0
        self.playbackRate = playbackRate.isFinite ? max(playbackRate, 0) : 0
        self.defaultPlaybackRate = defaultPlaybackRate.isFinite && defaultPlaybackRate > 0
            ? defaultPlaybackRate
            : 1
        itemRatingKey = item.ratingKey
        externalContentIdentifier = Self.scopedIdentifier(
            serverIdentifier: serverIdentifier,
            ratingKey: item.ratingKey
        )
        collectionIdentifier = item.nowPlayingCollectionRatingKey.flatMap {
            Self.scopedIdentifier(serverIdentifier: serverIdentifier, ratingKey: $0)
        }

        if mediaKind == .audio {
            albumTrackNumber = item.index.flatMap { $0 > 0 ? $0 : nil }
            discNumber = item.parentIndex.flatMap { $0 > 0 ? $0 : nil }
        } else {
            albumTrackNumber = nil
            discNumber = nil
        }

        if let queuePosition,
           let queueCount,
           queuePosition > 0,
           queuePosition <= queueCount {
            queueIndex = queuePosition - 1
            self.queueCount = queueCount
        } else {
            queueIndex = nil
            self.queueCount = nil
        }
    }

    private static func mediaKind(for type: String?) -> MediaKind {
        switch type?.lowercased() {
        case "track":
            .audio
        case "movie":
            .movie
        case "episode":
            .television
        default:
            .video
        }
    }

    private static func scopedIdentifier(
        serverIdentifier: String?,
        ratingKey: String
    ) -> String? {
        guard let serverIdentifier = serverIdentifier?.nilIfBlank else {
            return nil
        }

        return "plex:\(serverIdentifier.utf8.count):\(serverIdentifier):\(ratingKey.utf8.count):\(ratingKey)"
    }

    var nowPlayingInfo: [String: Any] {
        nowPlayingInfo(artwork: nil)
    }

    func nowPlayingInfo(
        artwork: MPMediaItemArtwork?,
        languageOptions: PlexNowPlayingLanguageOptions? = nil
    ) -> [String: Any] {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyMediaType: NSNumber(value: mediaType.rawValue),
            MPNowPlayingInfoPropertyMediaType: NSNumber(value: nowPlayingMediaType.rawValue),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: NSNumber(value: elapsedTime),
            MPNowPlayingInfoPropertyPlaybackRate: NSNumber(value: playbackRate),
            MPNowPlayingInfoPropertyDefaultPlaybackRate: NSNumber(value: defaultPlaybackRate),
            MPNowPlayingInfoPropertyExcludeFromSuggestions: true
        ]

        if let artist {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let albumTitle {
            info[MPMediaItemPropertyAlbumTitle] = albumTitle
        }
        if let genre {
            info[MPMediaItemPropertyGenre] = genre
        }
        if let duration {
            info[MPMediaItemPropertyPlaybackDuration] = NSNumber(value: duration)
        }
        if let creditsStartTime {
            info[MPNowPlayingInfoPropertyCreditsStartTime] = NSNumber(value: creditsStartTime)
        }
        if let externalContentIdentifier {
            info[MPNowPlayingInfoPropertyExternalContentIdentifier] = externalContentIdentifier
        }
        if let collectionIdentifier {
            info[MPNowPlayingInfoCollectionIdentifier] = collectionIdentifier
        }
        if let albumTrackNumber {
            info[MPMediaItemPropertyAlbumTrackNumber] = NSNumber(value: albumTrackNumber)
        }
        if let discNumber {
            info[MPMediaItemPropertyDiscNumber] = NSNumber(value: discNumber)
        }
        if let queueIndex, let queueCount {
            info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = NSNumber(value: queueIndex)
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = NSNumber(value: queueCount)
        }
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        if let languageOptions, languageOptions.hasAvailableOptions {
            info[MPNowPlayingInfoPropertyAvailableLanguageOptions] = languageOptions.groups
            info[MPNowPlayingInfoPropertyCurrentLanguageOptions] = languageOptions.currentOptions
        }

        return info
    }

    private var mediaType: MPMediaType {
        switch mediaKind {
        case .audio:
            .anyAudio
        case .movie:
            .movie
        case .television:
            .tvShow
        case .video:
            .anyVideo
        }
    }

    private var nowPlayingMediaType: MPNowPlayingInfoMediaType {
        switch mediaKind {
        case .audio:
            .audio
        case .movie, .television, .video:
            .video
        }
    }
}

#if os(macOS)
struct PlexRemotePlaybackActions: Sendable {
    let play: @MainActor @Sendable () -> Void
    let pause: @MainActor @Sendable () -> Void
    let togglePlayPause: @MainActor @Sendable () -> Void
    let stop: @MainActor @Sendable () -> Void
    let seek: @MainActor @Sendable (TimeInterval) -> Void
    let skip: @MainActor @Sendable (TimeInterval) -> Void
    let selectAudioStream: @MainActor @Sendable (Int) -> Void
    let selectSubtitleStream: @MainActor @Sendable (Int?) -> Void
    let changePlaybackRate: @MainActor @Sendable (PlexPlaybackRate) -> Void
    let changeShuffle: @MainActor @Sendable (Bool) -> Void
    let changeRepeatMode: @MainActor @Sendable (PlexPlaybackRepeatMode) -> Void
    let previous: @MainActor @Sendable () -> Void
    let next: @MainActor @Sendable () -> Void
}

@MainActor
final class PlexNowPlayingController {
    private let infoCenter: MPNowPlayingInfoCenter
    private let commandCenter: MPRemoteCommandCenter
    private var commandTargets: [(command: MPRemoteCommand, target: Any)] = []
    private var artwork: MPMediaItemArtwork?
    private var languageOptions = PlexNowPlayingLanguageOptions()
    private var canChangeLanguageOptions = false
    private var lastMetadata: PlexNowPlayingMetadata?
    private var lastStatus: PlexPlaybackStatus?

    init(
        infoCenter: MPNowPlayingInfoCenter = .default(),
        commandCenter: MPRemoteCommandCenter = .shared()
    ) {
        self.infoCenter = infoCenter
        self.commandCenter = commandCenter
    }

    func activate(
        metadata: PlexNowPlayingMetadata,
        status: PlexPlaybackStatus,
        actions: PlexRemotePlaybackActions,
        canGoPrevious: Bool,
        canGoNext: Bool,
        canSeek: Bool,
        languageOptions: PlexNowPlayingLanguageOptions,
        canChangeLanguageOptions: Bool,
        canChangeShuffle: Bool,
        isShuffled: Bool,
        repeatMode: PlexPlaybackRepeatMode,
        canRepeatAll: Bool
    ) {
        deactivate()
        self.languageOptions = languageOptions
        self.canChangeLanguageOptions = canChangeLanguageOptions
        registerCommands(actions: actions, canRepeatAll: canRepeatAll)
        updateNavigation(canGoPrevious: canGoPrevious, canGoNext: canGoNext)
        updateSeeking(canSeek: canSeek)
        updateLanguageCommandAvailability()
        updateShuffle(canChange: canChangeShuffle, isShuffled: isShuffled)
        updateRepeatMode(repeatMode)
        publish(metadata: metadata, status: status)
    }

    func updateNavigation(canGoPrevious: Bool, canGoNext: Bool) {
        commandCenter.previousTrackCommand.isEnabled = canGoPrevious
        commandCenter.nextTrackCommand.isEnabled = canGoNext
    }

    func updateSeeking(canSeek: Bool) {
        commandCenter.changePlaybackPositionCommand.isEnabled = canSeek
        commandCenter.skipBackwardCommand.isEnabled = canSeek
        commandCenter.skipForwardCommand.isEnabled = canSeek
    }

    func updateLanguageOptions(_ languageOptions: PlexNowPlayingLanguageOptions) {
        self.languageOptions = languageOptions
        updateLanguageCommandAvailability()
        guard let lastMetadata, let lastStatus else {
            return
        }
        publish(metadata: lastMetadata, status: lastStatus)
    }

    func updateLanguageCommandAvailability(canChange: Bool) {
        canChangeLanguageOptions = canChange
        applyLanguageCommandAvailability()
    }

    func updateShuffle(canChange: Bool, isShuffled: Bool) {
        commandCenter.changeShuffleModeCommand.currentShuffleType = isShuffled ? .items : .off
        commandCenter.changeShuffleModeCommand.isEnabled = canChange
    }

    func updateRepeatMode(_ repeatMode: PlexPlaybackRepeatMode) {
        commandCenter.changeRepeatModeCommand.currentRepeatType = repeatMode.remoteCommandValue
        commandCenter.changeRepeatModeCommand.isEnabled = true
    }

    func updateArtwork(
        _ image: CGImage,
        itemRatingKey: String
    ) {
        guard let lastMetadata,
              lastMetadata.itemRatingKey == itemRatingKey,
              let lastStatus else {
            return
        }
        artwork = PlexNowPlayingArtworkFactory.make(from: image)
        publish(metadata: lastMetadata, status: lastStatus)
    }

    func update(
        metadata: PlexNowPlayingMetadata,
        status: PlexPlaybackStatus,
        force: Bool = false
    ) {
        guard force
            || status != lastStatus
            || metadata.publicationFingerprint != lastMetadata?.publicationFingerprint else {
            return
        }

        publish(metadata: metadata, status: status)
    }

    func deactivate() {
        for commandTarget in commandTargets {
            commandTarget.command.removeTarget(commandTarget.target)
        }
        commandTargets.removeAll()
        setOwnedCommandsEnabled(false)
        infoCenter.nowPlayingInfo = nil
        infoCenter.playbackState = .stopped
        artwork = nil
        languageOptions = PlexNowPlayingLanguageOptions()
        canChangeLanguageOptions = false
        lastMetadata = nil
        lastStatus = nil
    }

    private func registerCommands(
        actions: PlexRemotePlaybackActions,
        canRepeatAll: Bool
    ) {
        setOwnedCommandsEnabled(true)
        addTarget(to: commandCenter.playCommand) { _ in
            Task { @MainActor in
                actions.play()
            }
            return .success
        }
        addTarget(to: commandCenter.pauseCommand) { _ in
            Task { @MainActor in
                actions.pause()
            }
            return .success
        }
        addTarget(to: commandCenter.togglePlayPauseCommand) { _ in
            Task { @MainActor in
                actions.togglePlayPause()
            }
            return .success
        }
        addTarget(to: commandCenter.stopCommand) { _ in
            Task { @MainActor in
                actions.stop()
            }
            return .success
        }
        addTarget(to: commandCenter.changePlaybackPositionCommand) { event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            guard positionEvent.positionTime.isFinite else {
                return .commandFailed
            }

            Task { @MainActor in
                actions.seek(positionEvent.positionTime)
            }
            return .success
        }
        commandCenter.skipBackwardCommand.preferredIntervals = [
            NSNumber(value: PlexPlaybackSeek.skipInterval)
        ]
        addTarget(to: commandCenter.skipBackwardCommand) { event in
            guard let skipEvent = event as? MPSkipIntervalCommandEvent,
                  let offset = PlexPlaybackSkipDirection.backward.offset(
                      for: skipEvent.interval
                  ) else {
                return .commandFailed
            }

            Task { @MainActor in
                actions.skip(offset)
            }
            return .success
        }
        commandCenter.skipForwardCommand.preferredIntervals = [
            NSNumber(value: PlexPlaybackSeek.skipInterval)
        ]
        addTarget(to: commandCenter.skipForwardCommand) { event in
            guard let skipEvent = event as? MPSkipIntervalCommandEvent,
                  let offset = PlexPlaybackSkipDirection.forward.offset(
                      for: skipEvent.interval
                  ) else {
                return .commandFailed
            }

            Task { @MainActor in
                actions.skip(offset)
            }
            return .success
        }
        addTarget(to: commandCenter.enableLanguageOptionCommand) { event in
            guard let languageEvent = event as? MPChangeLanguageOptionCommandEvent,
                  languageEvent.setting == .nowPlayingItemOnly,
                  let selection = PlexNowPlayingLanguageSelection(
                      languageOption: languageEvent.languageOption
                  ) else {
                return .commandFailed
            }

            Task { @MainActor in
                switch selection {
                case .audio(let streamID):
                    actions.selectAudioStream(streamID)
                case .subtitle(let streamID):
                    actions.selectSubtitleStream(streamID)
                }
            }
            return .success
        }
        addTarget(to: commandCenter.disableLanguageOptionCommand) { event in
            guard let languageEvent = event as? MPChangeLanguageOptionCommandEvent,
                  languageEvent.setting == .nowPlayingItemOnly,
                  case .subtitle = PlexNowPlayingLanguageSelection(
                      languageOption: languageEvent.languageOption
                  ) else {
                return .commandFailed
            }

            Task { @MainActor in
                actions.selectSubtitleStream(nil)
            }
            return .success
        }
        commandCenter.changePlaybackRateCommand.supportedPlaybackRates = PlexPlaybackRate.allCases.map {
            NSNumber(value: $0.rawValue)
        }
        addTarget(to: commandCenter.changePlaybackRateCommand) { event in
            guard let rateEvent = event as? MPChangePlaybackRateCommandEvent,
                  let playbackRate = PlexPlaybackRate(
                      remoteCommandValue: rateEvent.playbackRate
                  ) else {
                return .commandFailed
            }

            Task { @MainActor in
                actions.changePlaybackRate(playbackRate)
            }
            return .success
        }
        addTarget(to: commandCenter.changeShuffleModeCommand) { event in
            guard let shuffleEvent = event as? MPChangeShuffleModeCommandEvent else {
                return .commandFailed
            }

            let isShuffled: Bool
            switch shuffleEvent.shuffleType {
            case .off:
                isShuffled = false
            case .items:
                isShuffled = true
            case .collections:
                return .commandFailed
            @unknown default:
                return .commandFailed
            }

            Task { @MainActor in
                actions.changeShuffle(isShuffled)
            }
            return .success
        }
        addTarget(to: commandCenter.changeRepeatModeCommand) { event in
            guard let repeatEvent = event as? MPChangeRepeatModeCommandEvent,
                  let repeatMode = PlexPlaybackRepeatMode(
                      remoteCommandValue: repeatEvent.repeatType
                  ), repeatMode != .all || canRepeatAll else {
                return .commandFailed
            }

            Task { @MainActor in
                actions.changeRepeatMode(repeatMode)
            }
            return .success
        }
        addTarget(to: commandCenter.previousTrackCommand) { _ in
            Task { @MainActor in
                actions.previous()
            }
            return .success
        }
        addTarget(to: commandCenter.nextTrackCommand) { _ in
            Task { @MainActor in
                actions.next()
            }
            return .success
        }
    }

    private func addTarget(
        to command: MPRemoteCommand,
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        let target = command.addTarget(handler: handler)
        commandTargets.append((command, target))
    }

    private func setOwnedCommandsEnabled(_ isEnabled: Bool) {
        commandCenter.playCommand.isEnabled = isEnabled
        commandCenter.pauseCommand.isEnabled = isEnabled
        commandCenter.togglePlayPauseCommand.isEnabled = isEnabled
        commandCenter.stopCommand.isEnabled = isEnabled
        commandCenter.changePlaybackPositionCommand.isEnabled = isEnabled
        commandCenter.skipBackwardCommand.isEnabled = isEnabled
        commandCenter.skipForwardCommand.isEnabled = isEnabled
        if !isEnabled {
            commandCenter.enableLanguageOptionCommand.isEnabled = false
            commandCenter.disableLanguageOptionCommand.isEnabled = false
        }
        commandCenter.changePlaybackRateCommand.isEnabled = isEnabled
        commandCenter.changeShuffleModeCommand.isEnabled = isEnabled
        commandCenter.changeRepeatModeCommand.isEnabled = isEnabled
        if !isEnabled {
            commandCenter.changePlaybackRateCommand.supportedPlaybackRates = []
            commandCenter.skipBackwardCommand.preferredIntervals = []
            commandCenter.skipForwardCommand.preferredIntervals = []
            commandCenter.changeShuffleModeCommand.currentShuffleType = .off
            commandCenter.changeRepeatModeCommand.currentRepeatType = .off
        }
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.nextTrackCommand.isEnabled = false
    }

    private func publish(metadata: PlexNowPlayingMetadata, status: PlexPlaybackStatus) {
        infoCenter.nowPlayingInfo = metadata.nowPlayingInfo(
            artwork: artwork,
            languageOptions: languageOptions
        )
        infoCenter.playbackState = status.nowPlayingPlaybackState
        lastMetadata = metadata
        lastStatus = status
    }

    private func updateLanguageCommandAvailability() {
        applyLanguageCommandAvailability()
    }

    private func applyLanguageCommandAvailability() {
        commandCenter.enableLanguageOptionCommand.isEnabled =
            canChangeLanguageOptions && languageOptions.hasAvailableOptions
        commandCenter.disableLanguageOptionCommand.isEnabled =
            canChangeLanguageOptions && languageOptions.hasSelectedSubtitle
    }
}
#endif

private extension PlexMediaItem {
    var nowPlayingCollectionRatingKey: String? {
        switch type?.lowercased() {
        case "episode":
            grandparentRatingKey?.nilIfBlank ?? parentRatingKey?.nilIfBlank
        case "track":
            parentRatingKey?.nilIfBlank ?? grandparentRatingKey?.nilIfBlank
        default:
            nil
        }
    }
}

#if os(macOS)
private extension PlexPlaybackRepeatMode {
    init?(remoteCommandValue: MPRepeatType) {
        switch remoteCommandValue {
        case .off:
            self = .off
        case .one:
            self = .one
        case .all:
            self = .all
        @unknown default:
            return nil
        }
    }

    var remoteCommandValue: MPRepeatType {
        switch self {
        case .off: .off
        case .one: .one
        case .all: .all
        }
    }
}

private extension PlexPlaybackStatus {
    var nowPlayingPlaybackState: MPNowPlayingPlaybackState {
        switch self {
        case .playing:
            .playing
        case .paused:
            .paused
        case .preparing, .buffering:
            .interrupted
        case .idle, .ended, .failed:
            .stopped
        }
    }
}
#endif
