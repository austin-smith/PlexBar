import PlexModels
import Foundation
import os

actor PlexDownloadTransferCoordinator {
    static let backgroundSessionIdentifier = "\(AppConstants.bundleIdentifier).downloads"
    private static let logger = Logger(
        subsystem: AppConstants.bundleIdentifier,
        category: "Downloads"
    )

    private let registry: PlexDownloadTransferRegistry
    private let packageStore: PlexDownloadPackageStore
    private let handoffStore: PlexDownloadHandoffStore
    private let session: PlexDownloadTransferSession

    private var eventTask: Task<Void, Never>?
    private var progressByTransferID: [UUID: PlexDownloadTransferProgress] = [:]
    private var started = false

    init(
        registry: PlexDownloadTransferRegistry,
        packageStore: PlexDownloadPackageStore,
        handoffStore: PlexDownloadHandoffStore,
        session: PlexDownloadTransferSession
    ) {
        self.registry = registry
        self.packageStore = packageStore
        self.handoffStore = handoffStore
        self.session = session
    }

    static func live(
        rootURL: URL = PlexDownloadPackageStore.defaultRootURL(),
        packageStore: PlexDownloadPackageStore? = nil
    ) -> PlexDownloadTransferCoordinator {
        let packageStore = packageStore ?? PlexDownloadPackageStore(rootURL: rootURL)
        let handoffStore = PlexDownloadHandoffStore(rootURL: rootURL)
        return PlexDownloadTransferCoordinator(
            registry: PlexDownloadTransferRegistry(rootURL: rootURL),
            packageStore: packageStore,
            handoffStore: handoffStore,
            session: .background(
                identifier: backgroundSessionIdentifier,
                handoffStore: handoffStore
            )
        )
    }

    static func inert(
        rootURL: URL,
        packageStore: PlexDownloadPackageStore? = nil
    ) -> PlexDownloadTransferCoordinator {
        let packageStore = packageStore ?? PlexDownloadPackageStore(rootURL: rootURL)
        let handoffStore = PlexDownloadHandoffStore(rootURL: rootURL)
        return PlexDownloadTransferCoordinator(
            registry: PlexDownloadTransferRegistry(rootURL: rootURL),
            packageStore: packageStore,
            handoffStore: handoffStore,
            session: .inert()
        )
    }

    func start() async throws {
        guard !started else {
            return
        }
        started = true
        let events = session.events
        eventTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else {
                    return
                }
                await self?.handle(event)
            }
        }
        do {
            try await recover()
        } catch {
            Self.logger.error(
                "Download transfer recovery failed: \(error.localizedDescription, privacy: .public)"
            )
            eventTask?.cancel()
            eventTask = nil
            started = false
            throw error
        }
    }

    func schedule(
        _ transferRequest: PlexDownloadTransferRequest,
        transferID: UUID = UUID(),
        createdAt: Date = Date(),
        authorizationCheck: @escaping @Sendable () async -> Bool = { true }
    ) async throws -> PlexDownloadTransferRecord {
        try await start()
        guard await authorizationCheck() else {
            throw PlexDownloadTransferError.authorizationExpired
        }
        guard Self.isValid(request: transferRequest.request) else {
            throw PlexDownloadTransferError.invalidRequest
        }
        try await packageStore.validateMetadata(
            identity: transferRequest.packageIdentity,
            title: transferRequest.title,
            decisionData: transferRequest.decisionData,
            mediaFileExtension: transferRequest.mediaFileExtension
        )
        let existingRecords = try await registry.records()
        guard !existingRecords.contains(where: {
            $0.id == transferID
                || $0.packageIdentity.packageID
                    == transferRequest.packageIdentity.packageID
        }) else {
            throw PlexDownloadTransferError.duplicateTransfer
        }
        guard let taskIdentifier = session.createTask(
            with: transferRequest.request,
            transferID: transferID
        ) else {
            throw PlexDownloadTransferError.taskCreationFailed
        }

        var record = PlexDownloadTransferRecord(
            id: transferID,
            packageIdentity: transferRequest.packageIdentity,
            title: transferRequest.title,
            mediaType: transferRequest.mediaType,
            decisionData: transferRequest.decisionData,
            mediaFileExtension: transferRequest.mediaFileExtension,
            contentType: transferRequest.contentType,
            taskIdentifier: taskIdentifier,
            createdAt: createdAt
        )
        do {
            try await registry.save(record)
        } catch {
            await session.cancelTask(withIdentifier: taskIdentifier)
            throw PlexDownloadTransferError.registryUnavailable
        }

        guard await authorizationCheck() else {
            await session.cancelTask(withIdentifier: taskIdentifier)
            do {
                try await registry.remove(withID: transferID)
            } catch {
                throw PlexDownloadTransferError.registryUnavailable
            }
            throw PlexDownloadTransferError.authorizationExpired
        }

        await session.resumeTask(withIdentifier: taskIdentifier)
        record.state = .transferring
        try? await registry.save(record)
        return record
    }

    func cancel(transferID: UUID) async throws {
        guard let record = try await registry.record(withID: transferID) else {
            try? handoffStore.removeHandoff(for: transferID)
            progressByTransferID.removeValue(forKey: transferID)
            return
        }
        await session.cancelTask(withIdentifier: record.taskIdentifier)
        try? handoffStore.removeHandoff(for: transferID)
        try await registry.remove(withID: transferID)
        progressByTransferID.removeValue(forKey: transferID)
    }

    func pause(transferID: UUID) async throws {
        guard var record = try await registry.record(withID: transferID),
              record.state == .transferring else {
            return
        }
        await session.suspendTask(withIdentifier: record.taskIdentifier)
        record.state = .paused
        try await registry.save(record)
    }

    func resume(transferID: UUID) async throws {
        guard var record = try await registry.record(withID: transferID),
              record.state == .paused else {
            return
        }
        await session.resumeTask(withIdentifier: record.taskIdentifier)
        record.state = .transferring
        record.failure = nil
        try await registry.save(record)
    }

    func records() async throws -> [PlexDownloadTransferRecord] {
        try await registry.records()
    }

    func progress(for transferID: UUID) -> PlexDownloadTransferProgress? {
        progressByTransferID[transferID]
    }

    func progressSnapshot() -> [UUID: PlexDownloadTransferProgress] {
        progressByTransferID
    }

    private func recover() async throws {
        _ = try await packageStore.reconcile()
        var records = try await registry.records()
        let recordIDs = Set(records.map(\.id))
        _ = try handoffStore.reconcile(validTransferIDs: recordIDs)
        let tasks = await session.tasks()
        let taskByIdentifier = Dictionary(uniqueKeysWithValues: tasks.map {
            ($0.taskIdentifier, $0)
        })

        for task in tasks where !Self.task(task, belongsTo: records) {
            await session.cancelTask(withIdentifier: task.taskIdentifier)
        }

        for record in records {
            do {
                if try await packageStore.package(
                    withID: record.packageIdentity.packageID
                ) != nil {
                    await session.cancelTask(withIdentifier: record.taskIdentifier)
                    try? handoffStore.removeHandoff(for: record.id)
                    try await registry.remove(withID: record.id)
                    progressByTransferID.removeValue(forKey: record.id)
                    continue
                }
            } catch {
                await markFailed(record, failure: .publication)
                continue
            }

            switch handoffStore.handoff(for: record.id) {
            case .success(.some(let handoff)):
                await publish(handoff: handoff, for: record)
                continue
            case .failure:
                await markFailed(record, failure: .handoff)
                continue
            case .success(.none):
                break
            }

            guard let task = taskByIdentifier[record.taskIdentifier],
                  task.taskDescription == record.id.uuidString else {
                await markFailed(record, failure: .missingTask)
                continue
            }
            if record.state == .failed {
                await session.cancelTask(withIdentifier: task.taskIdentifier)
                continue
            }
            switch task.state {
            case .running:
                await markTransferring(record, task: task)
            case .suspended:
                if record.state == .paused {
                    progressByTransferID[record.id] = PlexDownloadTransferProgress(
                        transferID: record.id,
                        bytesReceived: max(task.countOfBytesReceived, 0),
                        bytesExpected: task.countOfBytesExpectedToReceive > 0
                            ? task.countOfBytesExpectedToReceive
                            : nil
                    )
                } else {
                    await session.resumeTask(withIdentifier: task.taskIdentifier)
                    await markTransferring(record, task: task)
                }
            case .canceling, .completed:
                await markFailed(record, failure: .transfer)
            }
        }
        records = try await registry.records()
        _ = try handoffStore.reconcile(validTransferIDs: Set(records.map(\.id)))
    }

    private func handle(_ event: PlexDownloadTransferEvent) async {
        switch event {
        case let .progress(taskIdentifier, description, received, expected):
            guard let record = await matchingRecord(
                taskIdentifier: taskIdentifier,
                description: description
            ) else {
                return
            }
            progressByTransferID[record.id] = PlexDownloadTransferProgress(
                transferID: record.id,
                bytesReceived: max(received, 0),
                bytesExpected: expected > 0 ? expected : nil
            )
            guard record.state != .paused else {
                return
            }
            if record.state != .transferring {
                var updated = record
                updated.state = .transferring
                updated.failure = nil
                try? await registry.save(updated)
            }

        case let .waitingForConnectivity(taskIdentifier, description):
            guard let record = await matchingRecord(
                taskIdentifier: taskIdentifier,
                description: description
            ) else {
                return
            }
            guard record.state != .paused else {
                return
            }
            if record.state != .transferring {
                var updated = record
                updated.state = .transferring
                updated.failure = nil
                try? await registry.save(updated)
            }

        case let .handoffCompleted(taskIdentifier, description, result):
            guard let record = await matchingRecord(
                taskIdentifier: taskIdentifier,
                description: description
            ) else {
                if case .success(let handoff) = result {
                    try? handoffStore.removeHandoff(for: handoff.manifest.transferID)
                }
                return
            }
            switch result {
            case .success(let handoff):
                var downloaded = record
                downloaded.state = .downloaded
                downloaded.failure = nil
                try? await registry.save(downloaded)
                await publish(handoff: handoff, for: downloaded)
            case .failure(let error):
                await markFailed(
                    record,
                    failure: Self.failure(for: error)
                )
            }

        case let .taskCompleted(taskIdentifier, description, errorCode):
            guard let record = await matchingRecord(
                taskIdentifier: taskIdentifier,
                description: description
            ) else {
                return
            }
            guard record.state != .failed else {
                return
            }
            if errorCode != nil {
                try? handoffStore.removeHandoff(for: record.id)
                await markFailed(record, failure: .transfer)
            } else if case .success(.some(let handoff)) = handoffStore.handoff(
                for: record.id
            ) {
                await publish(handoff: handoff, for: record)
            } else {
                await markFailed(record, failure: .handoff)
            }
        }
    }

    private func publish(
        handoff: PlexDownloadHandoff,
        for record: PlexDownloadTransferRecord
    ) async {
        var publishing = record
        publishing.state = .publishing
        publishing.failure = nil
        try? await registry.save(publishing)

        do {
            _ = try await packageStore.publish(
                identity: record.packageIdentity,
                title: record.title,
                mediaType: record.mediaType,
                decisionData: record.decisionData,
                downloadedFileURL: handoff.mediaURL,
                mediaFileExtension: handoff.manifest.suggestedFileExtension
                    ?? record.mediaFileExtension,
                contentType: handoff.manifest.contentType ?? record.contentType,
                completedAt: handoff.manifest.completedAt
            )
            try? handoffStore.removeHandoff(for: record.id)
            try await registry.remove(withID: record.id)
            progressByTransferID.removeValue(forKey: record.id)
        } catch {
            try? handoffStore.removeHandoff(for: record.id)
            await markFailed(publishing, failure: .publication)
        }
    }

    private func matchingRecord(
        taskIdentifier: Int,
        description: String?
    ) async -> PlexDownloadTransferRecord? {
        guard let description,
              let transferID = UUID(uuidString: description),
              let record = try? await registry.record(withID: transferID),
              record.taskIdentifier == taskIdentifier else {
            if let record = try? await registry.records().first(where: {
                $0.taskIdentifier == taskIdentifier
            }) {
                await markFailed(record, failure: .invalidTaskIdentity)
            }
            await session.cancelTask(withIdentifier: taskIdentifier)
            return nil
        }
        return record
    }

    private func markTransferring(
        _ record: PlexDownloadTransferRecord,
        task: PlexDownloadTransferTaskSnapshot
    ) async {
        var updated = record
        updated.state = .transferring
        updated.failure = nil
        try? await registry.save(updated)
        progressByTransferID[record.id] = PlexDownloadTransferProgress(
            transferID: record.id,
            bytesReceived: max(task.countOfBytesReceived, 0),
            bytesExpected: task.countOfBytesExpectedToReceive > 0
                ? task.countOfBytesExpectedToReceive
                : nil
        )
    }

    private func markFailed(
        _ record: PlexDownloadTransferRecord,
        failure: PlexDownloadTransferFailure
    ) async {
        var updated = record
        updated.state = .failed
        updated.failure = failure
        try? await registry.save(updated)
        progressByTransferID.removeValue(forKey: record.id)
    }

    private static func isValid(request: URLRequest) -> Bool {
        guard request.httpMethod == "GET",
              request.httpBody == nil,
              request.httpBodyStream == nil,
              let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "http" || components.scheme == "https",
              components.host?.nilIfBlank != nil,
              components.user == nil,
              components.password == nil,
              request.value(forHTTPHeaderField: "X-Plex-Token")?.nilIfBlank != nil else {
            return false
        }
        return true
    }

    private static func task(
        _ task: PlexDownloadTransferTaskSnapshot,
        belongsTo records: [PlexDownloadTransferRecord]
    ) -> Bool {
        guard let description = task.taskDescription,
              let transferID = UUID(uuidString: description) else {
            return false
        }
        return records.contains {
            $0.id == transferID && $0.taskIdentifier == task.taskIdentifier
        }
    }

    private static func failure(
        for error: PlexDownloadHandoffError
    ) -> PlexDownloadTransferFailure {
        switch error {
        case .invalidTransferIdentity:
            .invalidTaskIdentity
        case .invalidResponse, .serverStatus:
            .serverResponse
        case .invalidTemporaryFile,
             .existingHandoffIsInvalid,
             .publicationFailed:
            .handoff
        }
    }
}
