import Foundation

struct PlexDownloadTransferSession: Sendable {
    typealias CreateTask = @Sendable (URLRequest, String) -> Int?
    typealias Tasks = @Sendable () async -> [PlexDownloadTransferTaskSnapshot]
    typealias TaskAction = @Sendable (Int) async -> Void

    let events: AsyncStream<PlexDownloadTransferEvent>
    private let createTaskImplementation: CreateTask
    private let tasksImplementation: Tasks
    private let resumeTaskImplementation: TaskAction
    private let suspendTaskImplementation: TaskAction
    private let cancelTaskImplementation: TaskAction

    init(
        events: AsyncStream<PlexDownloadTransferEvent>,
        createTask: @escaping CreateTask,
        tasks: @escaping Tasks,
        resumeTask: @escaping TaskAction,
        cancelTask: @escaping TaskAction,
        suspendTask: @escaping TaskAction = { _ in }
    ) {
        self.events = events
        createTaskImplementation = createTask
        tasksImplementation = tasks
        resumeTaskImplementation = resumeTask
        suspendTaskImplementation = suspendTask
        cancelTaskImplementation = cancelTask
    }

    func createTask(with request: URLRequest, transferID: UUID) -> Int? {
        createTaskImplementation(request, transferID.uuidString)
    }

    func tasks() async -> [PlexDownloadTransferTaskSnapshot] {
        await tasksImplementation()
    }

    func resumeTask(withIdentifier identifier: Int) async {
        await resumeTaskImplementation(identifier)
    }

    func suspendTask(withIdentifier identifier: Int) async {
        await suspendTaskImplementation(identifier)
    }

    func cancelTask(withIdentifier identifier: Int) async {
        await cancelTaskImplementation(identifier)
    }

    static func background(
        identifier: String,
        handoffStore: PlexDownloadHandoffStore
    ) -> PlexDownloadTransferSession {
        let stream = AsyncStream.makeStream(of: PlexDownloadTransferEvent.self)
        let delegate = PlexDownloadURLSessionDelegate(
            handoffStore: handoffStore,
            onEvent: { event in
                stream.continuation.yield(event)
            }
        )
        let configuration = backgroundConfiguration(identifier: identifier)

        let queue = OperationQueue()
        queue.name = "\(identifier).delegate"
        queue.maxConcurrentOperationCount = 1
        let owner = PlexDownloadURLSessionOwner(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: queue
        )

        return PlexDownloadTransferSession(
            events: stream.stream,
            createTask: { request, description in
                owner.createTask(with: request, description: description)
            },
            tasks: {
                await owner.tasks()
            },
            resumeTask: { identifier in
                await owner.resumeTask(withIdentifier: identifier)
            },
            cancelTask: { identifier in
                await owner.cancelTask(withIdentifier: identifier)
            },
            suspendTask: { identifier in
                await owner.suspendTask(withIdentifier: identifier)
            }
        )
    }

    static func backgroundConfiguration(
        identifier: String
    ) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        return configuration
    }

    static func inert() -> PlexDownloadTransferSession {
        let stream = AsyncStream.makeStream(of: PlexDownloadTransferEvent.self)
        return PlexDownloadTransferSession(
            events: stream.stream,
            createTask: { _, _ in nil },
            tasks: { [] },
            resumeTask: { _ in },
            cancelTask: { _ in },
            suspendTask: { _ in }
        )
    }
}

private final class PlexDownloadURLSessionOwner: @unchecked Sendable {
    private let session: URLSession

    init(
        configuration: URLSessionConfiguration,
        delegate: URLSessionDelegate,
        delegateQueue: OperationQueue
    ) {
        session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: delegateQueue
        )
    }

    func createTask(with request: URLRequest, description: String) -> Int {
        let task = session.downloadTask(with: request)
        task.taskDescription = description
        return task.taskIdentifier
    }

    func tasks() async -> [PlexDownloadTransferTaskSnapshot] {
        await withCheckedContinuation { continuation in
            session.getAllTasks { tasks in
                continuation.resume(returning: tasks.map(Self.snapshot))
            }
        }
    }

    func resumeTask(withIdentifier identifier: Int) async {
        guard let task = await task(withIdentifier: identifier) else {
            return
        }
        task.resume()
    }

    func suspendTask(withIdentifier identifier: Int) async {
        guard let task = await task(withIdentifier: identifier) else {
            return
        }
        task.suspend()
    }

    func cancelTask(withIdentifier identifier: Int) async {
        guard let task = await task(withIdentifier: identifier) else {
            return
        }
        task.cancel()
    }

    private func task(withIdentifier identifier: Int) async -> URLSessionTask? {
        await withCheckedContinuation { continuation in
            session.getAllTasks { tasks in
                continuation.resume(returning: tasks.first {
                    $0.taskIdentifier == identifier
                })
            }
        }
    }

    private static func snapshot(_ task: URLSessionTask) -> PlexDownloadTransferTaskSnapshot {
        PlexDownloadTransferTaskSnapshot(
            taskIdentifier: task.taskIdentifier,
            taskDescription: task.taskDescription,
            state: state(task.state),
            countOfBytesReceived: task.countOfBytesReceived,
            countOfBytesExpectedToReceive: task.countOfBytesExpectedToReceive
        )
    }

    private static func state(
        _ state: URLSessionTask.State
    ) -> PlexDownloadTransferTaskSnapshot.State {
        switch state {
        case .running:
            .running
        case .suspended:
            .suspended
        case .canceling:
            .canceling
        case .completed:
            .completed
        @unknown default:
            .completed
        }
    }
}

private final class PlexDownloadURLSessionDelegate:
    NSObject,
    URLSessionDownloadDelegate,
    @unchecked Sendable
{
    private let handoffStore: PlexDownloadHandoffStore
    private let onEvent: @Sendable (PlexDownloadTransferEvent) -> Void

    init(
        handoffStore: PlexDownloadHandoffStore,
        onEvent: @escaping @Sendable (PlexDownloadTransferEvent) -> Void
    ) {
        self.handoffStore = handoffStore
        self.onEvent = onEvent
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let result: Result<PlexDownloadHandoff, PlexDownloadHandoffError>
        if let description = downloadTask.taskDescription,
           let transferID = UUID(uuidString: description) {
            result = handoffStore.accept(
                temporaryFileURL: location,
                transferID: transferID,
                response: downloadTask.response
            )
        } else {
            result = .failure(.invalidTransferIdentity)
        }
        onEvent(.handoffCompleted(
            taskIdentifier: downloadTask.taskIdentifier,
            taskDescription: downloadTask.taskDescription,
            result: result
        ))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onEvent(.progress(
            taskIdentifier: downloadTask.taskIdentifier,
            taskDescription: downloadTask.taskDescription,
            bytesReceived: totalBytesWritten,
            bytesExpected: totalBytesExpectedToWrite
        ))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        let errorCode = error.map { ($0 as NSError).code }
        onEvent(.taskCompleted(
            taskIdentifier: task.taskIdentifier,
            taskDescription: task.taskDescription,
            errorCode: errorCode
        ))
    }

    func urlSession(
        _ session: URLSession,
        taskIsWaitingForConnectivity task: URLSessionTask
    ) {
        onEvent(.waitingForConnectivity(
            taskIdentifier: task.taskIdentifier,
            taskDescription: task.taskDescription
        ))
    }
}
