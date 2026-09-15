import Foundation
import Testing
@testable import PlexBar

@Suite(.serialized)
struct PlexDownloadTransferCoordinatorTests {
    @Test func nativeBackgroundConfigurationUsesOneRecoverableNonCachingSession() {
        let identifier = PlexDownloadTransferCoordinator.backgroundSessionIdentifier
        let configuration = PlexDownloadTransferSession.backgroundConfiguration(
            identifier: identifier
        )

        #expect(identifier == "com.crapshack.PlexBar.downloads")
        #expect(configuration.identifier == identifier)
        #expect(configuration.sessionSendsLaunchEvents)
        #expect(!configuration.isDiscretionary)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
    }

    @Test func schedulePersistsIdentityBeforeResumingWithoutPersistingSecrets() async throws {
        let fixture = try TransferFixture()
        defer { fixture.remove() }

        let record = try await fixture.coordinator.schedule(
            fixture.transferRequest(),
            transferID: fixture.transferID,
            createdAt: fixture.createdAt
        )

        #expect(record.id == fixture.transferID)
        #expect(record.state == .transferring)
        #expect(fixture.sessionHarness.resumedTaskIDs == [record.taskIdentifier])
        let records = try await fixture.registry.records()
        #expect(records.count == 1)
        #expect(records.first?.id == fixture.transferID)
        #expect(records.first?.packageIdentity == fixture.packageIdentity)

        let registryData = try Data(contentsOf: fixture.registryURL)
        let registryText = try #require(String(data: registryData, encoding: .utf8))
        #expect(!registryText.contains("server-token-secret"))
        #expect(!registryText.contains("plex.test"))
    }

    @Test func invalidAndDuplicateRequestsNeverCreateASecondTask() async throws {
        let fixture = try TransferFixture()
        defer { fixture.remove() }
        var invalidRequest = fixture.mediaRequest
        invalidRequest.setValue(nil, forHTTPHeaderField: "X-Plex-Token")

        await #expect(throws: PlexDownloadTransferError.self) {
            _ = try await fixture.coordinator.schedule(PlexDownloadTransferRequest(
                packageIdentity: fixture.packageIdentity,
                title: "Episode",
                mediaType: "episode",
                decisionData: fixture.decisionData,
                mediaFileExtension: "mp4",
                contentType: "video/mp4",
                request: invalidRequest
            ))
        }
        _ = try await fixture.coordinator.schedule(
            fixture.transferRequest(),
            transferID: fixture.transferID
        )
        await #expect(throws: PlexDownloadTransferError.self) {
            _ = try await fixture.coordinator.schedule(fixture.transferRequest())
        }

        #expect(fixture.sessionHarness.createdTaskIDs.count == 1)
    }

    @Test func expiredAuthorizationNeverResumesAndRemovesTheSuspendedRecord() async throws {
        let fixture = try TransferFixture()
        defer { fixture.remove() }
        let authorization = TransferAuthorizationSequence([true, false])

        await #expect(throws: PlexDownloadTransferError.authorizationExpired) {
            _ = try await fixture.coordinator.schedule(
                fixture.transferRequest(),
                transferID: fixture.transferID,
                authorizationCheck: {
                    authorization.next()
                }
            )
        }

        #expect(fixture.sessionHarness.createdTaskIDs == [100])
        #expect(fixture.sessionHarness.resumedTaskIDs.isEmpty)
        #expect(fixture.sessionHarness.cancelledTaskIDs == [100])
        #expect(try await fixture.registry.records().isEmpty)
    }

    @Test func completionPublishesTheAtomicPackageAndClearsTransferState() async throws {
        let fixture = try TransferFixture()
        defer { fixture.remove() }
        let record = try await fixture.coordinator.schedule(
            fixture.transferRequest(),
            transferID: fixture.transferID
        )
        let mediaData = Data("background-media".utf8)
        let temporaryURL = try fixture.makeFile(data: mediaData)
        let handoff = try fixture.handoffStore.accept(
            temporaryFileURL: temporaryURL,
            transferID: fixture.transferID,
            response: fixture.response()
        ).get()

        fixture.sessionHarness.emit(.progress(
            taskIdentifier: record.taskIdentifier,
            taskDescription: fixture.transferID.uuidString,
            bytesReceived: 8,
            bytesExpected: Int64(mediaData.count)
        ))
        fixture.sessionHarness.emit(.handoffCompleted(
            taskIdentifier: record.taskIdentifier,
            taskDescription: fixture.transferID.uuidString,
            result: .success(handoff)
        ))
        fixture.sessionHarness.emit(.taskCompleted(
            taskIdentifier: record.taskIdentifier,
            taskDescription: fixture.transferID.uuidString,
            errorCode: nil
        ))

        #expect(try await eventually {
            try await fixture.registry.records().isEmpty
        })
        let package = try #require(try await fixture.packageStore.package(
            withID: fixture.packageIdentity.packageID
        ))
        #expect(package.manifest.identity == fixture.packageIdentity)
        #expect(package.manifest.mediaFileName == "media.mp4")
        #expect(package.manifest.contentType == "video/mp4")
        #expect(try Data(contentsOf: package.mediaURL) == mediaData)
        #expect(try fixture.handoffStore.handoff(for: fixture.transferID).get() == nil)
        #expect(await fixture.coordinator.progress(for: fixture.transferID) == nil)
    }

    @Test func relaunchRecoveryResumesTheExactSuspendedTaskAndCancelsOrphans() async throws {
        let fixture = try TransferFixture()
        defer { fixture.remove() }
        let record = fixture.record(taskIdentifier: 77, state: .scheduled)
        try await fixture.registry.save(record)
        fixture.sessionHarness.addTask(
            identifier: 77,
            description: fixture.transferID.uuidString,
            state: .suspended,
            received: 40,
            expected: 100
        )
        fixture.sessionHarness.addTask(
            identifier: 78,
            description: UUID().uuidString,
            state: .running
        )
        let relaunchedRegistry = PlexDownloadTransferRegistry(rootURL: fixture.rootURL)
        let relaunchedCoordinator = PlexDownloadTransferCoordinator(
            registry: relaunchedRegistry,
            packageStore: PlexDownloadPackageStore(rootURL: fixture.rootURL),
            handoffStore: fixture.handoffStore,
            session: fixture.sessionHarness.session
        )

        try await relaunchedCoordinator.start()

        #expect(fixture.sessionHarness.resumedTaskIDs == [77])
        #expect(fixture.sessionHarness.cancelledTaskIDs == [78])
        let recovered = try #require(try await relaunchedRegistry.record(
            withID: fixture.transferID
        ))
        #expect(recovered.state == .transferring)
        #expect(await relaunchedCoordinator.progress(for: fixture.transferID) == PlexDownloadTransferProgress(
            transferID: fixture.transferID,
            bytesReceived: 40,
            bytesExpected: 100
        ))
    }

    @Test func explicitPauseSurvivesRelaunchWithoutResumingTheTask() async throws {
        let fixture = try TransferFixture()
        defer { fixture.remove() }
        try await fixture.registry.save(fixture.record(taskIdentifier: 77, state: .paused))
        fixture.sessionHarness.addTask(
            identifier: 77,
            description: fixture.transferID.uuidString,
            state: .suspended,
            received: 40,
            expected: 100
        )
        let relaunchedRegistry = PlexDownloadTransferRegistry(rootURL: fixture.rootURL)
        let relaunchedCoordinator = PlexDownloadTransferCoordinator(
            registry: relaunchedRegistry,
            packageStore: PlexDownloadPackageStore(rootURL: fixture.rootURL),
            handoffStore: fixture.handoffStore,
            session: fixture.sessionHarness.session
        )

        try await relaunchedCoordinator.start()

        #expect(fixture.sessionHarness.resumedTaskIDs.isEmpty)
        #expect(fixture.sessionHarness.suspendedTaskIDs.isEmpty)
        let recovered = try #require(try await relaunchedRegistry.record(
            withID: fixture.transferID
        ))
        #expect(recovered.state == .paused)
        #expect(await relaunchedCoordinator.progress(for: fixture.transferID) == PlexDownloadTransferProgress(
            transferID: fixture.transferID,
            bytesReceived: 40,
            bytesExpected: 100
        ))
    }

    @Test func pauseAndResumeControlOnlyThePersistedTransfer() async throws {
        let fixture = try TransferFixture()
        defer { fixture.remove() }
        let record = try await fixture.coordinator.schedule(
            fixture.transferRequest(),
            transferID: fixture.transferID
        )

        try await fixture.coordinator.pause(transferID: fixture.transferID)
        let paused = try #require(try await fixture.registry.record(withID: fixture.transferID))
        #expect(paused.state == .paused)
        #expect(fixture.sessionHarness.suspendedTaskIDs == [record.taskIdentifier])

        try await fixture.coordinator.resume(transferID: fixture.transferID)
        let resumed = try #require(try await fixture.registry.record(withID: fixture.transferID))
        #expect(resumed.state == .transferring)
        #expect(fixture.sessionHarness.resumedTaskIDs == [record.taskIdentifier, record.taskIdentifier])
    }

    @Test func relaunchPublishesAnAcceptedHandoffEvenWhenTheTaskIsGone() async throws {
        let fixture = try TransferFixture()
        defer { fixture.remove() }
        try await fixture.registry.save(fixture.record(taskIdentifier: 91, state: .downloaded))
        let mediaData = Data("handoff-survived-process-exit".utf8)
        _ = try fixture.handoffStore.accept(
            temporaryFileURL: fixture.makeFile(data: mediaData),
            transferID: fixture.transferID,
            response: fixture.response()
        ).get()
        let relaunchedRegistry = PlexDownloadTransferRegistry(rootURL: fixture.rootURL)
        let relaunchedPackageStore = PlexDownloadPackageStore(rootURL: fixture.rootURL)
        let relaunchedCoordinator = PlexDownloadTransferCoordinator(
            registry: relaunchedRegistry,
            packageStore: relaunchedPackageStore,
            handoffStore: fixture.handoffStore,
            session: fixture.sessionHarness.session
        )

        try await relaunchedCoordinator.start()

        #expect(try await relaunchedRegistry.records().isEmpty)
        let package = try #require(try await relaunchedPackageStore.package(
            withID: fixture.packageIdentity.packageID
        ))
        #expect(try Data(contentsOf: package.mediaURL) == mediaData)
    }

    @Test func missingTasksAndServerErrorsRemainExplicitFailures() async throws {
        let fixture = try TransferFixture()
        defer { fixture.remove() }
        try await fixture.registry.save(fixture.record(taskIdentifier: 55))
        try await fixture.coordinator.start()
        let missingTaskRecord = try #require(try await fixture.registry.record(
            withID: fixture.transferID
        ))
        #expect(missingTaskRecord.state == .failed)
        #expect(missingTaskRecord.failure == .missingTask)

        try await fixture.coordinator.cancel(transferID: fixture.transferID)
        let scheduled = try await fixture.coordinator.schedule(
            fixture.transferRequest(),
            transferID: fixture.transferID
        )
        fixture.sessionHarness.emit(.handoffCompleted(
            taskIdentifier: scheduled.taskIdentifier,
            taskDescription: fixture.transferID.uuidString,
            result: .failure(.serverStatus(401))
        ))
        fixture.sessionHarness.emit(.taskCompleted(
            taskIdentifier: scheduled.taskIdentifier,
            taskDescription: fixture.transferID.uuidString,
            errorCode: nil
        ))

        #expect(try await eventually {
            try await fixture.registry.record(withID: fixture.transferID)?.failure
                == .serverResponse
        })
        let serverFailure = try #require(try await fixture.registry.record(
            withID: fixture.transferID
        ))
        #expect(serverFailure.state == .failed)
        #expect(serverFailure.failure == .serverResponse)
    }

    @Test func cancellationIsExactAndIdempotent() async throws {
        let fixture = try TransferFixture()
        defer { fixture.remove() }
        let record = try await fixture.coordinator.schedule(
            fixture.transferRequest(),
            transferID: fixture.transferID
        )

        try await fixture.coordinator.cancel(transferID: fixture.transferID)
        try await fixture.coordinator.cancel(transferID: fixture.transferID)

        #expect(fixture.sessionHarness.cancelledTaskIDs == [record.taskIdentifier])
        #expect(try await fixture.registry.records().isEmpty)
    }
}

private final class TransferAuthorizationSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool]

    init(_ values: [Bool]) {
        self.values = values
    }

    func next() -> Bool {
        lock.withLock {
            values.isEmpty ? false : values.removeFirst()
        }
    }
}

private struct TransferFixture {
    let rootURL: URL
    let transferID = UUID(uuidString: "7B2138C7-AFE6-44CB-A0EC-176F1C4869EE")!
    let packageIdentity = PlexDownloadPackageIdentity(
        packageID: UUID(uuidString: "BB6DF0A6-1FAF-43D1-AAB4-F5529C7DF07C")!,
        accountID: 9,
        serverIdentifier: "server-id",
        queueID: 7,
        queueItemID: 11,
        metadataKey: "/library/metadata/42",
        ratingKey: "42"
    )
    let createdAt = Date(timeIntervalSince1970: 1_788_134_400)
    let registry: PlexDownloadTransferRegistry
    let packageStore: PlexDownloadPackageStore
    let handoffStore: PlexDownloadHandoffStore
    let sessionHarness: TransferSessionHarness
    let coordinator: PlexDownloadTransferCoordinator

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlexDownloadTransferCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        registry = PlexDownloadTransferRegistry(rootURL: rootURL)
        packageStore = PlexDownloadPackageStore(rootURL: rootURL)
        handoffStore = PlexDownloadHandoffStore(rootURL: rootURL)
        sessionHarness = TransferSessionHarness()
        coordinator = PlexDownloadTransferCoordinator(
            registry: registry,
            packageStore: packageStore,
            handoffStore: handoffStore,
            session: sessionHarness.session
        )
    }

    var registryURL: URL {
        rootURL
            .appendingPathComponent("Transfers", isDirectory: true)
            .appendingPathComponent("registry.json")
    }

    var mediaRequest: URLRequest {
        var request = URLRequest(
            url: URL(string: "https://plex.test/downloadQueue/7/item/11/media")!
        )
        request.httpMethod = "GET"
        request.setValue("server-token-secret", forHTTPHeaderField: "X-Plex-Token")
        return request
    }

    var decisionData: Data {
        Data(#"{"MediaContainer":{"allowSync":"1","Metadata":[{"ratingKey":"42","key":"/library/metadata/42","title":"Episode","type":"episode","Media":[]}]}}"#.utf8)
    }

    func transferRequest() -> PlexDownloadTransferRequest {
        PlexDownloadTransferRequest(
            packageIdentity: packageIdentity,
            title: "Episode",
            mediaType: "episode",
            decisionData: decisionData,
            mediaFileExtension: "mkv",
            contentType: "video/x-matroska",
            request: mediaRequest
        )
    }

    func record(
        taskIdentifier: Int,
        state: PlexDownloadTransferState = .scheduled
    ) -> PlexDownloadTransferRecord {
        PlexDownloadTransferRecord(
            id: transferID,
            packageIdentity: packageIdentity,
            title: "Episode",
            mediaType: "episode",
            decisionData: decisionData,
            mediaFileExtension: "mkv",
            contentType: "video/x-matroska",
            taskIdentifier: taskIdentifier,
            createdAt: createdAt,
            state: state
        )
    }

    func makeFile(data: Data) throws -> URL {
        let url = rootURL.appendingPathComponent("download-\(UUID().uuidString)")
        try data.write(to: url)
        return url
    }

    func response(statusCode: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(
            url: mediaRequest.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/2",
            headerFields: [
                "Content-Type": "video/mp4",
                "Content-Disposition": "attachment; filename=episode.mp4",
            ]
        )!
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private final class TransferSessionHarness: @unchecked Sendable {
    private let lock = NSLock()
    private let eventStream = AsyncStream.makeStream(of: PlexDownloadTransferEvent.self)
    private var nextTaskIdentifier = 100
    private var taskSnapshots: [Int: PlexDownloadTransferTaskSnapshot] = [:]
    private var _createdTaskIDs: [Int] = []
    private var _resumedTaskIDs: [Int] = []
    private var _suspendedTaskIDs: [Int] = []
    private var _cancelledTaskIDs: [Int] = []

    var session: PlexDownloadTransferSession {
        PlexDownloadTransferSession(
            events: eventStream.stream,
            createTask: { [weak self] request, description in
                self?.createTask(request: request, description: description)
            },
            tasks: { [weak self] in
                self?.snapshots ?? []
            },
            resumeTask: { [weak self] identifier in
                self?.resume(identifier: identifier)
            },
            cancelTask: { [weak self] identifier in
                self?.cancel(identifier: identifier)
            },
            suspendTask: { [weak self] identifier in
                self?.suspend(identifier: identifier)
            }
        )
    }

    var createdTaskIDs: [Int] { withLock { _createdTaskIDs } }
    var resumedTaskIDs: [Int] { withLock { _resumedTaskIDs } }
    var suspendedTaskIDs: [Int] { withLock { _suspendedTaskIDs } }
    var cancelledTaskIDs: [Int] { withLock { _cancelledTaskIDs } }
    private var snapshots: [PlexDownloadTransferTaskSnapshot] {
        withLock { Array(taskSnapshots.values) }
    }

    func addTask(
        identifier: Int,
        description: String?,
        state: PlexDownloadTransferTaskSnapshot.State,
        received: Int64 = 0,
        expected: Int64 = -1
    ) {
        withLock {
            taskSnapshots[identifier] = PlexDownloadTransferTaskSnapshot(
                taskIdentifier: identifier,
                taskDescription: description,
                state: state,
                countOfBytesReceived: received,
                countOfBytesExpectedToReceive: expected
            )
        }
    }

    func emit(_ event: PlexDownloadTransferEvent) {
        eventStream.continuation.yield(event)
    }

    private func createTask(request: URLRequest, description: String) -> Int {
        withLock {
            let identifier = nextTaskIdentifier
            nextTaskIdentifier += 1
            _createdTaskIDs.append(identifier)
            taskSnapshots[identifier] = PlexDownloadTransferTaskSnapshot(
                taskIdentifier: identifier,
                taskDescription: description,
                state: .suspended,
                countOfBytesReceived: 0,
                countOfBytesExpectedToReceive: -1
            )
            return identifier
        }
    }

    private func resume(identifier: Int) {
        withLock {
            guard let task = taskSnapshots[identifier] else { return }
            _resumedTaskIDs.append(identifier)
            taskSnapshots[identifier] = PlexDownloadTransferTaskSnapshot(
                taskIdentifier: identifier,
                taskDescription: task.taskDescription,
                state: .running,
                countOfBytesReceived: task.countOfBytesReceived,
                countOfBytesExpectedToReceive: task.countOfBytesExpectedToReceive
            )
        }
    }

    private func suspend(identifier: Int) {
        withLock {
            guard let task = taskSnapshots[identifier] else { return }
            _suspendedTaskIDs.append(identifier)
            taskSnapshots[identifier] = PlexDownloadTransferTaskSnapshot(
                taskIdentifier: identifier,
                taskDescription: task.taskDescription,
                state: .suspended,
                countOfBytesReceived: task.countOfBytesReceived,
                countOfBytesExpectedToReceive: task.countOfBytesExpectedToReceive
            )
        }
    }

    private func cancel(identifier: Int) {
        withLock {
            guard let task = taskSnapshots[identifier] else { return }
            _cancelledTaskIDs.append(identifier)
            taskSnapshots[identifier] = PlexDownloadTransferTaskSnapshot(
                taskIdentifier: identifier,
                taskDescription: task.taskDescription,
                state: .canceling,
                countOfBytesReceived: task.countOfBytesReceived,
                countOfBytesExpectedToReceive: task.countOfBytesExpectedToReceive
            )
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private func eventually(
    timeout: Duration = .seconds(2),
    condition: @escaping @Sendable () async throws -> Bool
) async throws -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if try await condition() {
            return true
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    return try await condition()
}
