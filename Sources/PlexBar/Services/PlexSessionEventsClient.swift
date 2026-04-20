import Foundation

struct PlexSessionEventsClient {
    typealias MonitorHandler = @Sendable (PlexSessionEvent) async throws -> Void
    typealias MonitorImplementation = @Sendable (PlexConnectionConfiguration, @escaping MonitorHandler) async throws -> Void
    private static let handshakeTimeout: Duration = .seconds(5)

    private let monitorImplementation: MonitorImplementation

    init(session: URLSession = .shared) {
        monitorImplementation = { configuration, onEvent in
            let endpoint = try Self.notificationsURL(using: configuration)
            let request = PlexRequestBuilder(clientContext: configuration.clientContext).request(
                url: endpoint,
                token: configuration.token
            )

            let task = session.webSocketTask(with: request)
            task.resume()

            do {
                try Task.checkCancellation()
                try await Self.confirmHandshake(for: task)
                try await onEvent(.connected)

                while !Task.isCancelled {
                    let message = try await task.receive()
                    let data = try Self.messageData(from: message)

                    for event in Self.decodeEventsIfPossible(from: data) {
                        try Task.checkCancellation()
                        try await onEvent(event)
                    }
                }
            } catch is CancellationError {
                task.cancel(with: .goingAway, reason: nil)
                throw CancellationError()
            } catch {
                task.cancel(with: .goingAway, reason: nil)
                throw error
            }
        }
    }

    init(monitorImplementation: @escaping MonitorImplementation) {
        self.monitorImplementation = monitorImplementation
    }

    func monitor(
        using configuration: PlexConnectionConfiguration,
        onEvent: @escaping MonitorHandler
    ) async throws {
        try await monitorImplementation(configuration, onEvent)
    }

    static func notificationsURL(using configuration: PlexConnectionConfiguration) throws -> URL {
        guard let endpoint = PlexURLBuilder.endpointURL(
            serverURL: configuration.serverURL,
            path: "/:/websockets/notifications"
        ), var components = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw PlexSessionEventsError.invalidServerURL
        }

        components.scheme = components.scheme == "https" ? "wss" : "ws"
        // Plex's published OpenAPI currently documents the singular path
        // `/:/websocket/notifications`, but the real server endpoint is the
        // plural `/:/websockets/notifications`, which is what PlexBar uses.

        guard let url = components.url else {
            throw PlexSessionEventsError.invalidServerURL
        }

        return url
    }

    static func decodeEvents(from data: Data) throws -> [PlexSessionEvent] {
        let envelope = try JSONDecoder().decode(PlexSessionNotificationEnvelope.self, from: data)
        return envelope.notificationContainer.sessionEvents
    }

    static func decodeEventsIfPossible(from data: Data) -> [PlexSessionEvent] {
        do {
            return try decodeEvents(from: data)
        } catch is DecodingError {
            return []
        } catch {
            return []
        }
    }

    static func confirmHandshake(
        sendPing: (@escaping @Sendable (Error?) -> Void) -> Void,
        timeout: Duration = handshakeTimeout
    ) async throws {
        let state = HandshakeContinuationState()
        let timeoutTask = Task {
            try await Task.sleep(for: timeout)
            state.resume(with: .failure(PlexSessionEventsError.handshakeTimedOut))
        }

        defer {
            timeoutTask.cancel()
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            state.store(continuation)
            sendPing { error in
                if let error {
                    state.resume(with: .failure(error))
                } else {
                    state.resume(with: .success(()))
                }
            }
        }
    }

    private static func messageData(from message: URLSessionWebSocketTask.Message) throws -> Data {
        switch message {
        case .data(let data):
            return data
        case .string(let string):
            guard let data = string.data(using: .utf8) else {
                throw PlexSessionEventsError.invalidMessageEncoding
            }

            return data
        @unknown default:
            throw PlexSessionEventsError.unsupportedMessage
        }
    }

    private static func confirmHandshake(for task: URLSessionWebSocketTask) async throws {
        try await confirmHandshake { completion in
            task.sendPing(pongReceiveHandler: completion)
        }
    }
}

enum PlexSessionEventsError: LocalizedError {
    case invalidServerURL
    case invalidMessageEncoding
    case unsupportedMessage
    case handshakeTimedOut

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "PlexBar could not build the Plex notifications websocket URL."
        case .invalidMessageEncoding:
            return "Plex returned a websocket message in an unreadable encoding."
        case .unsupportedMessage:
            return "Plex returned an unsupported websocket message."
        case .handshakeTimedOut:
            return "Plex did not respond to the websocket handshake in time."
        }
    }
}

private final class HandshakeContinuationState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var result: Result<Void, Error>?

    func store(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        if let result {
            lock.unlock()
            switch result {
            case .success:
                continuation.resume()
            case .failure(let error):
                continuation.resume(throwing: error)
            }
            return
        }

        self.continuation = continuation
        lock.unlock()
    }

    func resume(with result: Result<Void, Error>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }

        self.result = result
        guard let continuation else {
            lock.unlock()
            return
        }

        self.continuation = nil
        lock.unlock()

        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
