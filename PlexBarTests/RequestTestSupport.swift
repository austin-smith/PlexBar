import Foundation

func requestBodyData(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        return Data()
    }

    stream.open()
    defer { stream.close() }

    var body = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count >= 0 else {
            throw stream.streamError ?? URLError(.cannotDecodeContentData)
        }
        if count == 0 {
            break
        }
        body.append(buffer, count: count)
    }
    return body
}

final class RequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequest: URLRequest?
    private var storedRequests: [URLRequest] = []

    var request: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storedRequest
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    func record(_ request: URLRequest) {
        lock.lock()
        storedRequest = request
        storedRequests.append(request)
        lock.unlock()
    }
}

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
