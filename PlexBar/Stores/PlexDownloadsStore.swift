import PlexModels
import Foundation
import Observation

@MainActor
@Observable
final class PlexDownloadsStore {
    private(set) var jobs: [PlexDownloadJob] = []
    private(set) var downloadedMedia: [PlexOfflineMedia] = []
    private(set) var transferProgress: [UUID: PlexDownloadTransferProgress] = [:]
    private(set) var automaticDownloadRules: [PlexAutomaticDownloadRule] = []
    private(set) var refreshingAutomaticRuleIDs: Set<UUID> = []
    private(set) var creatingRatingKeys: Set<String> = []
    private(set) var syncErrorMessages: [UUID: String] = [:]
    private(set) var startupErrorMessage: String?

    @ObservationIgnored private let authStore: PlexAuthStore
    @ObservationIgnored private let connectionStore: PlexConnectionStore
    @ObservationIgnored private let browserStore: PlexBrowserStore
    @ObservationIgnored private let client: PlexAPIClient
    @ObservationIgnored private let creationStore: PlexDownloadCreationStore
    @ObservationIgnored private let transferCoordinator: PlexDownloadTransferCoordinator
    @ObservationIgnored private let packageStore: PlexDownloadPackageStore
    @ObservationIgnored private let jobRegistry: PlexDownloadJobRegistry
    @ObservationIgnored private let playbackRegistry: PlexOfflinePlaybackRegistry
    @ObservationIgnored private let preparedAssetStore: PlexDownloadPreparedAssetStore
    @ObservationIgnored private let automaticRuleRegistry: PlexAutomaticDownloadRuleRegistry
    @ObservationIgnored private let pollingInterval: Duration
    @ObservationIgnored private let automaticRefreshInterval: Duration
    @ObservationIgnored private var jobTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var automaticRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var restartPreparationJobIDs: Set<UUID> = []
    @ObservationIgnored private var loadedAccountScope: AccountScope?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private let maximumConcurrentJobs = 2

    init(
        authStore: PlexAuthStore,
        connectionStore: PlexConnectionStore,
        browserStore: PlexBrowserStore,
        client: PlexAPIClient,
        creationStore: PlexDownloadCreationStore,
        transferCoordinator: PlexDownloadTransferCoordinator,
        packageStore: PlexDownloadPackageStore,
        jobRegistry: PlexDownloadJobRegistry = PlexDownloadJobRegistry(),
        playbackRegistry: PlexOfflinePlaybackRegistry = PlexOfflinePlaybackRegistry(),
        preparedAssetStore: PlexDownloadPreparedAssetStore = PlexDownloadPreparedAssetStore(),
        automaticRuleRegistry: PlexAutomaticDownloadRuleRegistry = PlexAutomaticDownloadRuleRegistry(),
        pollingInterval: Duration = .seconds(2),
        automaticRefreshInterval: Duration = .seconds(15 * 60)
    ) {
        self.authStore = authStore
        self.connectionStore = connectionStore
        self.browserStore = browserStore
        self.client = client
        self.creationStore = creationStore
        self.transferCoordinator = transferCoordinator
        self.packageStore = packageStore
        self.jobRegistry = jobRegistry
        self.playbackRegistry = playbackRegistry
        self.preparedAssetStore = preparedAssetStore
        self.automaticRuleRegistry = automaticRuleRegistry
        self.pollingInterval = pollingInterval
        self.automaticRefreshInterval = automaticRefreshInterval
    }

    var activeJobs: [PlexDownloadJob] {
        jobs.filter { $0.state != .failed }
    }

    var failedJobs: [PlexDownloadJob] {
        jobs.filter { $0.state == .failed }
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        do {
            try await creationStore.start()
            try await loadAccountScopedState()
            try await reconcileWorkflowState()
            startupErrorMessage = nil
            if authStore.authenticatedUser != nil {
                await resumePendingJobs()
                await synchronizeOfflineProgress()
                await refreshAutomaticDownloads()
            }
            beginAutomaticRefreshLoop()
        } catch {
            startupErrorMessage = error.localizedDescription
        }
    }

    func reload() async {
        do {
            try await loadAccountScopedState()
            try await reconcileWorkflowState()
            await refreshAutomaticDownloads()
            startupErrorMessage = nil
        } catch {
            startupErrorMessage = error.localizedDescription
        }
    }

    func resumePendingJobs() async {
        do {
            try await loadAccountScopedState()
            try await reconcileWorkflowState()
            startPendingJobs()
            startupErrorMessage = nil
        } catch {
            startupErrorMessage = error.localizedDescription
        }
    }

    func containsDownload(for item: PlexMediaItem) -> Bool {
        guard let scope = currentAccountScope else { return false }
        return downloadedMedia.contains {
            $0.package.manifest.identity.ratingKey == item.ratingKey
                && $0.package.manifest.identity.accountID == scope.accountID
                && $0.package.manifest.identity.serverIdentifier == scope.serverIdentifier
        }
    }

    func isDownloading(_ item: PlexMediaItem) -> Bool {
        guard let scope = currentAccountScope else { return false }
        return creatingRatingKeys.contains(item.ratingKey)
            || jobs.contains {
                $0.packageIdentity.ratingKey == item.ratingKey
                    && $0.accountID == scope.accountID
                    && $0.packageIdentity.accountID == scope.accountID
                    && $0.packageIdentity.serverIdentifier == scope.serverIdentifier
                    && $0.state != .failed
            }
    }

    func canCreateDownload(
        for item: PlexMediaItem,
        libraryID explicitLibraryID: String? = nil
    ) -> Bool {
        guard item.supportsOfflineDownload,
              let libraryID = explicitLibraryID?.nilIfBlank
                ?? item.librarySectionID?.nilIfBlank else {
            return false
        }
        return creationStore.isCurrentlyAuthorized(forLibraryID: libraryID)
    }

    func canCreateAutomaticDownloadRule(for item: PlexMediaItem) -> Bool {
        guard item.supportsAutomaticOfflineDownloads,
              let libraryID = item.librarySectionID?.nilIfBlank else {
            return false
        }
        return creationStore.isCurrentlyAuthorized(forLibraryID: libraryID)
    }

    func download(
        _ candidate: PlexMediaItem,
        source requestedSource: PlexPlaybackSource? = nil
    ) async throws {
        guard candidate.supportsOfflineDownload else {
            throw PlexDownloadWorkflowError.unsupportedItem
        }
        guard !containsDownload(for: candidate) else {
            throw PlexDownloadWorkflowError.alreadyDownloaded
        }
        guard !isDownloading(candidate) else {
            throw PlexDownloadWorkflowError.alreadyInProgress
        }

        creatingRatingKeys.insert(candidate.ratingKey)
        defer { creatingRatingKeys.remove(candidate.ratingKey) }

        let item = try await browserStore.refreshedPlayableDetails(for: candidate)
        guard let source = requestedSource.flatMap({ requested in
            item.playbackSource(mediaIndex: requested.mediaIndex)
        }) ?? item.defaultPlaybackSource else {
            throw PlexDownloadWorkflowError.unsupportedItem
        }
        guard let libraryID = item.librarySectionID?.nilIfBlank
            ?? candidate.librarySectionID?.nilIfBlank else {
            throw PlexDownloadWorkflowError.missingLibrary
        }
        let authorization = try await creationStore.authorization(forLibraryID: libraryID)
        let configuration = try await connectionStore.currentConfiguration()
        guard configuration.serverIdentifier?.nilIfBlank == authorization.scope.serverIdentifier else {
            throw PlexDownloadCreationAuthorizationError.authorizationExpired
        }

        let decision = try creationStore.decisionParameters(
            for: item,
            source: source,
            sessionIdentifier: UUID().uuidString
        )
        let queue = try await client.fetchOrCreateDownloadQueue(using: configuration)
        let metadataKey = item.key?.nilIfBlank ?? "/library/metadata/\(item.ratingKey)"
        let added = try await client.addToDownloadQueue(
            keys: [metadataKey],
            queueID: queue.id,
            decision: decision,
            using: configuration
        )
        guard added.count == 1,
              let queueItem = added.first,
              queueItem.key == metadataKey else {
            throw PlexDownloadWorkflowError.invalidQueueResponse
        }

        let now = Date()
        let packageIdentity = PlexDownloadPackageIdentity(
            accountID: authorization.scope.accountID,
            serverIdentifier: authorization.scope.serverIdentifier,
            queueID: queue.id,
            queueItemID: queueItem.id,
            metadataKey: metadataKey,
            ratingKey: item.ratingKey
        )
        let job = PlexDownloadJob(
            id: packageIdentity.packageID,
            accountID: authorization.scope.accountID,
            packageIdentity: packageIdentity,
            libraryID: libraryID,
            title: item.title,
            mediaType: item.type,
            source: source,
            decisionParameters: decision,
            createdAt: now,
            updatedAt: now,
            state: .waitingForServer,
            serverPreparationProgress: nil,
            transferID: nil,
            errorMessage: nil
        )
        try await save(job)
        if let artworkPath = item.posterArtworkPath,
           let artworkData = try? await client.fetchDownloadArtwork(
               path: artworkPath,
               using: configuration
           ) {
            try? await preparedAssetStore.saveArtwork(
                artworkData,
                packageID: packageIdentity.packageID
            )
        }
        startPendingJobs()
    }

    func createAutomaticDownloadRule(
        for candidate: PlexMediaItem,
        policy: PlexAutomaticDownloadPolicy,
        keepsUpToDate: Bool,
        removesWatchedDownloads: Bool
    ) async throws {
        guard candidate.supportsAutomaticOfflineDownloads,
              let libraryID = candidate.librarySectionID?.nilIfBlank else {
            throw PlexDownloadWorkflowError.unsupportedAutomaticDownload
        }
        let authorization = try await creationStore.authorization(forLibraryID: libraryID)
        let configuration = try await currentConfiguration(for: authorization)
        let item = try await client.fetchMediaMetadata(
            ratingKey: candidate.ratingKey,
            using: configuration
        )
        guard item.supportsAutomaticOfflineDownloads,
              let childrenPath = item.childrenPath?.nilIfBlank else {
            throw PlexDownloadWorkflowError.unsupportedAutomaticDownload
        }
        guard !automaticDownloadRules.contains(where: {
            $0.serverIdentifier == authorization.scope.serverIdentifier
                && $0.sourceRatingKey == item.ratingKey
        }) else {
            throw PlexDownloadWorkflowError.automaticDownloadAlreadyExists
        }

        let rule = PlexAutomaticDownloadRule(
            id: UUID(),
            accountID: authorization.scope.accountID,
            serverIdentifier: authorization.scope.serverIdentifier,
            libraryID: libraryID,
            sourceRatingKey: item.ratingKey,
            sourceChildrenPath: childrenPath,
            sourceType: item.type?.lowercased() ?? "",
            title: item.title,
            posterPath: item.posterArtworkPath,
            policy: policy,
            keepsUpToDate: keepsUpToDate,
            removesWatchedDownloads: removesWatchedDownloads,
            createdAt: Date(),
            lastRefreshedAt: nil,
            lastErrorMessage: nil
        )
        try await automaticRuleRegistry.save(rule)
        automaticDownloadRules.append(rule)
        sortAutomaticDownloadRules()

        do {
            try await refreshAutomaticDownload(ruleID: rule.id, allowsNewDownloads: true)
        } catch {
            try? await automaticRuleRegistry.remove(withID: rule.id)
            automaticDownloadRules.removeAll { $0.id == rule.id }
            throw error
        }
    }

    func removeAutomaticDownloadRule(_ rule: PlexAutomaticDownloadRule) async throws {
        try await automaticRuleRegistry.remove(withID: rule.id)
        automaticDownloadRules.removeAll { $0.id == rule.id }
    }

    func refreshAutomaticDownloads() async {
        guard let accountID = authStore.authenticatedUser?.id,
              let serverIdentifier = currentServerIdentifier else {
            return
        }
        let matchingRules = automaticDownloadRules.filter {
            $0.accountID == accountID && $0.serverIdentifier == serverIdentifier
        }
        for rule in matchingRules {
            try? await refreshAutomaticDownload(
                ruleID: rule.id,
                allowsNewDownloads: rule.keepsUpToDate
            )
        }
    }

    private func beginAutomaticRefreshLoop() {
        guard automaticRefreshTask == nil else { return }
        let interval = automaticRefreshInterval
        automaticRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                guard let self else { return }
                await self.refreshAutomaticDownloads()
            }
        }
    }

    func refreshAutomaticDownload(ruleID: UUID) async throws {
        guard let rule = automaticDownloadRules.first(where: { $0.id == ruleID }) else {
            return
        }
        try await refreshAutomaticDownload(
            ruleID: ruleID,
            allowsNewDownloads: rule.keepsUpToDate
        )
    }

    private func refreshAutomaticDownload(
        ruleID: UUID,
        allowsNewDownloads: Bool
    ) async throws {
        guard refreshingAutomaticRuleIDs.insert(ruleID).inserted else { return }
        defer { refreshingAutomaticRuleIDs.remove(ruleID) }
        guard var rule = automaticDownloadRules.first(where: { $0.id == ruleID }) else {
            return
        }

        do {
            let authorization = try await creationStore.authorization(forLibraryID: rule.libraryID)
            guard authorization.scope.accountID == rule.accountID,
                  authorization.scope.serverIdentifier == rule.serverIdentifier else {
                throw PlexDownloadCreationAuthorizationError.authorizationExpired
            }
            let configuration = try await currentConfiguration(for: authorization)
            let episodes = try await episodes(for: rule, using: configuration)

            if rule.removesWatchedDownloads {
                let watchedRatingKeys = Set(
                    episodes.lazy.filter(\.isWatched).map(\.ratingKey)
                )
                let packagesToRemove = downloadedMedia.filter {
                    $0.package.manifest.identity.serverIdentifier == rule.serverIdentifier
                        && watchedRatingKeys.contains($0.item.ratingKey)
                }
                for media in packagesToRemove {
                    try await remove(packageID: media.id)
                }
            }

            var itemErrors: [String] = []
            if allowsNewDownloads {
                let eligibleEpisodes = episodes.filter(rule.policy.includes)
                for episode in eligibleEpisodes {
                    if containsDownload(for: episode) || isDownloading(episode) {
                        continue
                    }
                    if let failedJob = jobs.first(where: {
                        $0.packageIdentity.serverIdentifier == rule.serverIdentifier
                            && $0.packageIdentity.ratingKey == episode.ratingKey
                            && $0.state == .failed
                    }) {
                        await retry(jobID: failedJob.id)
                        continue
                    }
                    do {
                        try await download(episode)
                    } catch {
                        itemErrors.append("\(episode.title): \(error.localizedDescription)")
                    }
                }
            }

            rule.lastRefreshedAt = Date()
            rule.lastErrorMessage = itemErrors.first.map {
                itemErrors.count == 1 ? $0 : "\($0) (+\(itemErrors.count - 1) more)"
            }
            try await saveAutomaticDownloadRule(rule)
        } catch {
            rule.lastRefreshedAt = Date()
            rule.lastErrorMessage = error.localizedDescription
            try? await saveAutomaticDownloadRule(rule)
            throw error
        }
    }

    private func episodes(
        for rule: PlexAutomaticDownloadRule,
        using configuration: PlexConnectionConfiguration
    ) async throws -> [PlexMediaItem] {
        let firstLevel = try await allMedia(
            at: rule.sourceChildrenPath,
            using: configuration
        )
        var episodes = firstLevel.filter { $0.type?.lowercased() == "episode" }
        let seasons = firstLevel.filter { $0.type?.lowercased() == "season" }

        if rule.sourceType == "season", !seasons.isEmpty {
            throw PlexDownloadWorkflowError.invalidAutomaticDownloadHierarchy
        }
        for season in seasons {
            let detailedSeason: PlexMediaItem
            if season.childrenPath?.nilIfBlank != nil {
                detailedSeason = season
            } else {
                detailedSeason = try await client.fetchMediaMetadata(
                    ratingKey: season.ratingKey,
                    using: configuration
                )
            }
            guard let path = detailedSeason.childrenPath?.nilIfBlank else {
                throw PlexDownloadWorkflowError.invalidAutomaticDownloadHierarchy
            }
            let children = try await allMedia(at: path, using: configuration)
            episodes.append(contentsOf: children.filter {
                $0.type?.lowercased() == "episode"
            })
        }

        let unexpectedTypes = Set(firstLevel.compactMap { item -> String? in
            guard let type = item.type?.lowercased(), type != "episode", type != "season" else {
                return nil
            }
            return type
        })
        guard unexpectedTypes.isEmpty else {
            throw PlexDownloadWorkflowError.invalidAutomaticDownloadHierarchy
        }

        var seen: Set<String> = []
        return episodes
            .filter { seen.insert($0.ratingKey).inserted }
            .sorted {
                if $0.parentIndex != $1.parentIndex {
                    return ($0.parentIndex ?? 0) < ($1.parentIndex ?? 0)
                }
                if $0.index != $1.index {
                    return ($0.index ?? 0) < ($1.index ?? 0)
                }
                return $0.ratingKey.localizedStandardCompare($1.ratingKey) == .orderedAscending
            }
    }

    private func allMedia(
        at contentPath: String,
        using configuration: PlexConnectionConfiguration
    ) async throws -> [PlexMediaItem] {
        let pageSize = 100
        var items: [PlexMediaItem] = []
        var seenIDs: Set<String> = []
        var start = 0

        while true {
            let page = try await client.fetchMediaPage(
                contentPath: contentPath,
                using: configuration,
                start: start,
                size: pageSize
            )
            guard !page.items.isEmpty else { break }
            let newItems = page.items.filter { seenIDs.insert($0.id).inserted }
            guard !newItems.isEmpty else { break }
            items.append(contentsOf: newItems)
            start += page.items.count
            if let totalSize = page.totalSize, start >= totalSize {
                break
            }
            if page.totalSize == nil, page.items.count < pageSize {
                break
            }
        }
        return items
    }

    private func saveAutomaticDownloadRule(
        _ rule: PlexAutomaticDownloadRule
    ) async throws {
        try await automaticRuleRegistry.save(rule)
        if let index = automaticDownloadRules.firstIndex(where: { $0.id == rule.id }) {
            automaticDownloadRules[index] = rule
        } else {
            automaticDownloadRules.append(rule)
        }
        sortAutomaticDownloadRules()
    }

    private func sortAutomaticDownloadRules() {
        automaticDownloadRules.sort {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    func cancel(jobID: UUID) async {
        jobTasks[jobID]?.cancel()
        jobTasks[jobID] = nil
        restartPreparationJobIDs.remove(jobID)
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        if let transferID = job.transferID {
            try? await transferCoordinator.cancel(transferID: transferID)
        }
        await deleteServerQueueItemIfPossible(job)
        try? await jobRegistry.remove(withID: jobID)
        try? await preparedAssetStore.remove(packageID: jobID)
        jobs.removeAll { $0.id == jobID }
        transferProgress[jobID] = nil
        startPendingJobs()
    }

    func pause(jobID: UUID) async {
        guard var job = jobs.first(where: { $0.id == jobID }),
              job.state == .transferring,
              let transferID = job.transferID else {
            return
        }
        do {
            try await transferCoordinator.pause(transferID: transferID)
            jobTasks[jobID]?.cancel()
            jobTasks[jobID] = nil
            job.state = .paused
            job.updatedAt = Date()
            try await save(job)
            startPendingJobs()
        } catch {
            await fail(jobID: jobID, message: error.localizedDescription)
        }
    }

    func resume(jobID: UUID) async {
        guard var job = jobs.first(where: { $0.id == jobID }),
              job.state == .paused,
              let transferID = job.transferID else {
            return
        }
        do {
            try await transferCoordinator.resume(transferID: transferID)
            job.state = .transferring
            job.errorMessage = nil
            job.updatedAt = Date()
            try await save(job)
            startPendingJobs()
        } catch {
            await fail(jobID: jobID, message: error.localizedDescription)
        }
    }

    func retry(jobID: UUID) async {
        guard var job = jobs.first(where: { $0.id == jobID }), job.state == .failed else {
            return
        }
        if let transferID = job.transferID {
            try? await transferCoordinator.cancel(transferID: transferID)
        }
        job.state = .waitingForServer
        job.transferID = nil
        job.errorMessage = nil
        job.serverPreparationProgress = nil
        job.updatedAt = Date()
        do {
            try await save(job)
            restartPreparationJobIDs.insert(job.id)
            startPendingJobs()
        } catch {
            await fail(jobID: jobID, message: error.localizedDescription)
        }
    }

    func remove(packageID: UUID) async throws {
        try await packageStore.removePackage(withID: packageID)
        try await playbackRegistry.remove(packageID: packageID)
        downloadedMedia.removeAll { $0.id == packageID }
        syncErrorMessages[packageID] = nil
    }

    func playbackPresentation(for media: PlexOfflineMedia) async throws -> PlexPlaybackPresentation {
        guard let scope = currentAccountScope,
              let currentMedia = try await packageStore.offlineMedia(
                  withID: media.id,
                  accountID: scope.accountID,
                  serverIdentifier: scope.serverIdentifier
              ),
              let source = currentMedia.item.defaultPlaybackSource else {
            throw PlexDownloadWorkflowError.unavailableOfflineMedia
        }
        if let index = downloadedMedia.firstIndex(where: { $0.id == currentMedia.id }) {
            downloadedMedia[index] = currentMedia
        }
        let record = try await playbackRegistry.record(for: currentMedia.id)
        let duration = currentMedia.item.duration.map { TimeInterval($0) / 1_000 }
        let startTime = record.map { TimeInterval($0.position) / 1_000 }
            ?? currentMedia.item.viewOffset.map { TimeInterval($0) / 1_000 }
            ?? 0
        let mediaKind = PlexPlaybackMediaKind(media: currentMedia.item.media[source.mediaIndex])
        let plan = PlexPlaybackPlan(
            url: currentMedia.package.mediaURL,
            method: .directPlay,
            mediaKind: mediaKind,
            sessionIdentifier: UUID().uuidString,
            ratingKey: currentMedia.item.ratingKey,
            duration: duration,
            startTime: max(startTime, 0),
            source: source,
            usesServerMediaSelection: false
        )
        return PlexPlaybackPresentation(
            item: currentMedia.item,
            plan: plan,
            queue: nil,
            videoQuality: .original,
            serverIdentifier: currentMedia.package.manifest.identity.serverIdentifier,
            offlinePackageID: currentMedia.id
        )
    }

    func recordOfflineTimeline(
        packageID: UUID,
        update: PlexTimelineUpdate
    ) async -> PlexTimelineResponse? {
        guard let media = downloadedMedia.first(where: { $0.id == packageID }) else {
            return nil
        }
        do {
            var record = try await playbackRegistry.record(for: packageID)
                ?? PlexOfflinePlaybackRecord(
                    packageID: packageID,
                    accountID: media.package.manifest.identity.accountID,
                    serverIdentifier: media.package.manifest.identity.serverIdentifier,
                    ratingKey: media.item.ratingKey,
                    baselineViewOffset: media.item.viewOffset,
                    baselineViewCount: media.item.viewCount,
                    position: 0,
                    duration: max(update.duration, 0),
                    state: update.state,
                    updatedAt: Date(),
                    needsSync: false
                )
            record.position = max(update.time, 0)
            record.duration = max(update.duration, 0)
            record.state = update.state
            record.updatedAt = Date()
            record.needsSync = true
            try await playbackRegistry.save(record)
            return await synchronize(record)
        } catch {
            syncErrorMessages[packageID] = error.localizedDescription
            return nil
        }
    }

    func synchronizeOfflineProgress() async {
        guard let records = try? await playbackRegistry.records() else { return }
        for record in records where record.needsSync {
            _ = await synchronize(record)
        }
    }

    private func begin(jobID: UUID, restartingServerPreparation: Bool) {
        guard jobTasks[jobID] == nil,
              jobTasks.count < maximumConcurrentJobs else {
            if restartingServerPreparation {
                restartPreparationJobIDs.insert(jobID)
            }
            return
        }
        restartPreparationJobIDs.remove(jobID)
        jobTasks[jobID] = Task { [weak self] in
            guard let self else { return }
            defer {
                jobTasks[jobID] = nil
                startPendingJobs()
            }
            do {
                try await run(jobID: jobID, restartingServerPreparation: restartingServerPreparation)
            } catch is CancellationError {
                return
            } catch PlexDownloadWorkflowError.serverChanged {
                await fail(
                    jobID: jobID,
                    message: PlexDownloadWorkflowError.serverChanged.localizedDescription
                )
            } catch {
                await fail(jobID: jobID, message: error.localizedDescription)
            }
        }
    }

    private func startPendingJobs() {
        let availableSlots = maximumConcurrentJobs - jobTasks.count
        guard availableSlots > 0 else { return }
        let pending = jobs
            .filter {
                $0.state != .failed
                    && $0.state != .paused
                    && jobTasks[$0.id] == nil
            }
            .sorted {
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt < $1.createdAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            .prefix(availableSlots)
        for job in pending {
            begin(
                jobID: job.id,
                restartingServerPreparation: restartPreparationJobIDs.contains(job.id)
            )
        }
    }

    private func run(jobID: UUID, restartingServerPreparation: Bool) async throws {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        if job.state == .transferring, job.transferID != nil {
            try await monitorTransfer(jobID: jobID)
            return
        }
        try await prepare(jobID: jobID, restartingServerPreparation: restartingServerPreparation)
    }

    private func prepare(jobID: UUID, restartingServerPreparation: Bool) async throws {
        var didRestart = false
        while !Task.isCancelled {
            guard var job = jobs.first(where: { $0.id == jobID }) else { return }
            let configuration = try await currentConfiguration(for: job)
            let queueItems = try await client.fetchDownloadQueueItems(
                queueID: job.packageIdentity.queueID,
                itemIDs: [job.packageIdentity.queueItemID],
                using: configuration
            )
            guard queueItems.count == 1,
                  let queueItem = queueItems.first,
                  queueItem.id == job.packageIdentity.queueItemID,
                  queueItem.queueID == job.packageIdentity.queueID,
                  queueItem.key == job.packageIdentity.metadataKey else {
                throw PlexDownloadWorkflowError.invalidQueueResponse
            }

            job.serverPreparationProgress = queueItem.transcodeSession?.progress.map {
                min(max($0 / 100, 0), 1)
            }
            job.errorMessage = nil
            job.updatedAt = Date()
            try await save(job)

            switch queueItem.status {
            case .available:
                try await scheduleTransfer(for: job, configuration: configuration)
                try await monitorTransfer(jobID: jobID)
                return
            case .error, .expired:
                guard restartingServerPreparation, !didRestart else {
                    let message = queueItem.failureDescription
                        ?? "Plex could not prepare this item for download."
                    throw PlexDownloadWorkflowError.serverPreparationFailed(message)
                }
                try await client.restartDownloadQueueItems(
                    queueID: job.packageIdentity.queueID,
                    itemIDs: [job.packageIdentity.queueItemID],
                    using: configuration
                )
                didRestart = true
            case .deciding, .waiting, .processing:
                break
            }
            try await Task.sleep(for: pollingInterval)
        }
        throw CancellationError()
    }

    private func scheduleTransfer(
        for job: PlexDownloadJob,
        configuration: PlexConnectionConfiguration
    ) async throws {
        let document = try await client.fetchDownloadQueueDecisionDocument(
            queueID: job.packageIdentity.queueID,
            itemID: job.packageIdentity.queueItemID,
            using: configuration
        )
        let request = try client.downloadQueueMediaRequest(
            queueID: job.packageIdentity.queueID,
            itemID: job.packageIdentity.queueItemID,
            using: configuration
        )
        let transferID = UUID()
        let transferRequest = PlexDownloadTransferRequest(
            packageIdentity: job.packageIdentity,
            title: job.title,
            mediaType: job.mediaType,
            decisionData: document.data,
            mediaFileExtension: nil,
            contentType: nil,
            request: request
        )
        _ = try await creationStore.schedule(
            transferRequest,
            forLibraryID: job.libraryID,
            transferID: transferID
        )
        var updated = job
        updated.state = .transferring
        updated.serverPreparationProgress = 1
        updated.transferID = transferID
        updated.errorMessage = nil
        updated.updatedAt = Date()
        try await save(updated)
    }

    private func monitorTransfer(jobID: UUID) async throws {
        while !Task.isCancelled {
            guard let job = jobs.first(where: { $0.id == jobID }),
                  let transferID = job.transferID else {
                return
            }
            if try await packageStore.package(withID: job.packageIdentity.packageID) != nil {
                await finish(job)
                return
            }
            let records = try await transferCoordinator.records()
            guard let record = records.first(where: { $0.id == transferID }) else {
                throw PlexDownloadWorkflowError.unavailableOfflineMedia
            }
            if record.state == .failed {
                let message = record.failure.map { "Download failed (\($0.rawValue))." }
                    ?? "The background download failed."
                throw PlexDownloadWorkflowError.serverPreparationFailed(message)
            }
            if record.state == .paused {
                var paused = job
                paused.state = .paused
                paused.updatedAt = Date()
                try await save(paused)
                return
            }
            if let progress = await transferCoordinator.progress(for: transferID) {
                transferProgress[jobID] = progress
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw CancellationError()
    }

    private func finish(_ job: PlexDownloadJob) async {
        if let artworkData = try? await preparedAssetStore.artwork(packageID: job.id) {
            _ = try? await packageStore.installArtwork(artworkData, for: job.id)
        }
        try? await preparedAssetStore.remove(packageID: job.id)
        await deleteServerQueueItemIfPossible(job)
        try? await jobRegistry.remove(withID: job.id)
        jobs.removeAll { $0.id == job.id }
        transferProgress[job.id] = nil
        do {
            downloadedMedia = try await accountScopedDownloadedMedia()
        } catch {
            startupErrorMessage = error.localizedDescription
        }
    }

    private func reconcileWorkflowState() async throws {
        let transfers = try await transferCoordinator.records()
        for job in jobs {
            if try await packageStore.package(withID: job.id) != nil {
                await finish(job)
                continue
            }
            if let transfer = transfers.first(where: {
                $0.packageIdentity.packageID == job.packageIdentity.packageID
            }) {
                var recovered = job
                recovered.transferID = transfer.id
                recovered.updatedAt = Date()
                switch transfer.state {
                case .paused:
                    recovered.state = .paused
                    recovered.errorMessage = nil
                case .failed:
                    recovered.state = .failed
                    recovered.errorMessage = transfer.failure.map {
                        "Download failed (\($0.rawValue))."
                    } ?? "The background download failed."
                case .scheduled, .transferring, .downloaded, .publishing:
                    recovered.state = .transferring
                    recovered.errorMessage = nil
                }
                try await save(recovered)
            } else if job.state == .transferring || job.state == .paused {
                var missing = job
                missing.state = .failed
                missing.errorMessage = "The background download task is no longer available."
                missing.updatedAt = Date()
                try await save(missing)
            }
        }
    }

    private func fail(jobID: UUID, message: String) async {
        guard var job = jobs.first(where: { $0.id == jobID }) else { return }
        job.state = .failed
        job.errorMessage = message
        job.updatedAt = Date()
        try? await save(job)
        transferProgress[jobID] = nil
    }

    private func save(_ job: PlexDownloadJob) async throws {
        try await jobRegistry.save(job)
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        } else {
            jobs.append(job)
        }
        jobs.sort { $0.createdAt < $1.createdAt }
    }

    private func currentConfiguration(
        for job: PlexDownloadJob
    ) async throws -> PlexConnectionConfiguration {
        let configuration = try await connectionStore.currentConfiguration()
        guard job.packageIdentity.accountID == job.accountID,
              configuration.serverIdentifier?.nilIfBlank == job.packageIdentity.serverIdentifier,
              authStore.authenticatedUser?.id == job.accountID else {
            throw PlexDownloadWorkflowError.serverChanged
        }
        return configuration
    }

    private func currentConfiguration(
        for authorization: PlexDownloadCreationAuthorization
    ) async throws -> PlexConnectionConfiguration {
        let configuration = try await connectionStore.currentConfiguration()
        guard configuration.serverIdentifier?.nilIfBlank == authorization.scope.serverIdentifier,
              creationStore.isCurrent(authorization) else {
            throw PlexDownloadCreationAuthorizationError.authorizationExpired
        }
        return configuration
    }

    private func deleteServerQueueItemIfPossible(_ job: PlexDownloadJob) async {
        guard let configuration = try? await currentConfiguration(for: job) else { return }
        try? await client.deleteDownloadQueueItems(
            queueID: job.packageIdentity.queueID,
            itemIDs: [job.packageIdentity.queueItemID],
            using: configuration
        )
    }

    private func synchronize(
        _ originalRecord: PlexOfflinePlaybackRecord
    ) async -> PlexTimelineResponse? {
        guard originalRecord.needsSync else { return nil }
        do {
            let configuration = try await connectionStore.currentConfiguration()
            guard let accountID = originalRecord.accountID,
                  authStore.authenticatedUser?.id == accountID,
                  configuration.serverIdentifier?.nilIfBlank == originalRecord.serverIdentifier else {
                return nil
            }
            let serverItem = try await client.fetchMediaMetadata(
                ratingKey: originalRecord.ratingKey,
                using: configuration
            )
            guard Self.normalizedOffset(serverItem.viewOffset)
                    == Self.normalizedOffset(originalRecord.baselineViewOffset),
                  Self.normalizedCount(serverItem.viewCount)
                    == Self.normalizedCount(originalRecord.baselineViewCount) else {
                syncErrorMessages[originalRecord.packageID] = PlexDownloadWorkflowError
                    .staleOfflineProgress.localizedDescription
                return nil
            }
            let endpoints = try await browserStore.downloadProviderEndpoints(using: configuration)
            guard let timelinePath = endpoints.timelinePath else {
                throw PlexAPIError.missingLibraryTimelineFeature
            }
            let update = PlexTimelineUpdate(
                ratingKey: originalRecord.ratingKey,
                state: originalRecord.state,
                time: originalRecord.position,
                duration: originalRecord.duration,
                sessionIdentifier: UUID().uuidString,
                continuing: false,
                offline: true
            )
            let response = try await client.reportTimeline(
                update,
                endpointPath: timelinePath,
                using: configuration
            )
            let synchronizedItem = try await client.fetchMediaMetadata(
                ratingKey: originalRecord.ratingKey,
                using: configuration
            )
            var synced = originalRecord
            synced.baselineViewOffset = synchronizedItem.viewOffset
            synced.baselineViewCount = synchronizedItem.viewCount
            synced.needsSync = false
            try await playbackRegistry.save(synced)
            syncErrorMessages[originalRecord.packageID] = nil
            return response
        } catch {
            syncErrorMessages[originalRecord.packageID] = error.localizedDescription
            return nil
        }
    }

    private var currentServerIdentifier: String? {
        connectionStore.activeConnection?.serverID
            ?? connectionStore.settings.selectedServerIdentifier?.nilIfBlank
    }

    private struct AccountScope: Equatable {
        let accountID: Int
        let serverIdentifier: String
    }

    private var currentAccountScope: AccountScope? {
        guard let accountID = authStore.authenticatedUser?.id,
              accountID > 0,
              let serverIdentifier = currentServerIdentifier?.nilIfBlank else {
            return nil
        }
        return AccountScope(accountID: accountID, serverIdentifier: serverIdentifier)
    }

    private func loadAccountScopedState() async throws {
        let scope = currentAccountScope
        if scope != loadedAccountScope {
            for task in jobTasks.values {
                task.cancel()
            }
            jobTasks.removeAll()
            restartPreparationJobIDs.removeAll()
            transferProgress.removeAll()
            syncErrorMessages.removeAll()
            loadedAccountScope = scope
        }

        guard let scope else {
            jobs = []
            downloadedMedia = []
            automaticDownloadRules = []
            return
        }
        jobs = try await jobRegistry.jobs().filter {
            $0.accountID == scope.accountID
                && $0.packageIdentity.accountID == scope.accountID
                && $0.packageIdentity.serverIdentifier == scope.serverIdentifier
        }
        downloadedMedia = try await accountScopedDownloadedMedia(scope: scope)
        automaticDownloadRules = try await automaticRuleRegistry.rules().filter {
            $0.accountID == scope.accountID
                && $0.serverIdentifier == scope.serverIdentifier
        }
    }

    private func accountScopedDownloadedMedia(
        scope explicitScope: AccountScope? = nil
    ) async throws -> [PlexOfflineMedia] {
        guard let scope = explicitScope ?? currentAccountScope else { return [] }
        return try await packageStore.offlineMedia(
            accountID: scope.accountID,
            serverIdentifier: scope.serverIdentifier
        )
    }

    private static func normalizedOffset(_ value: Int?) -> Int {
        max(value ?? 0, 0)
    }

    private static func normalizedCount(_ value: Int?) -> Int {
        max(value ?? 0, 0)
    }

}

extension PlexMediaItem {
    var supportsOfflineDownload: Bool {
        guard isPlayable, let type = type?.lowercased() else { return false }
        return ["movie", "episode", "track"].contains(type)
    }

    var supportsAutomaticOfflineDownloads: Bool {
        guard let type = type?.lowercased() else { return false }
        return type == "show" || type == "season"
    }
}
