import Foundation
import Security
import Testing
@testable import PlexBar

private final class TestKeychainBackend: PlexKeychainBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var activeCallCount = 0
    private var recordedMaximumActiveCallCount = 0

    var maximumActiveCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedMaximumActiveCallCount
    }

    func read(service: String, account: String) -> String? {
        beginCall()
        defer { endCall() }
        Thread.sleep(forTimeInterval: 0.001)

        lock.lock()
        defer { lock.unlock() }
        return values[key(service: service, account: account)]
    }

    func write(_ value: String, service: String, account: String) {
        beginCall()
        defer { endCall() }
        Thread.sleep(forTimeInterval: 0.001)

        lock.lock()
        values[key(service: service, account: account)] = value
        lock.unlock()
    }

    func delete(service: String, account: String) {
        beginCall()
        defer { endCall() }
        Thread.sleep(forTimeInterval: 0.001)

        lock.lock()
        values[key(service: service, account: account)] = nil
        lock.unlock()
    }

    private func beginCall() {
        lock.lock()
        activeCallCount += 1
        recordedMaximumActiveCallCount = max(recordedMaximumActiveCallCount, activeCallCount)
        lock.unlock()
    }

    private func endCall() {
        lock.lock()
        activeCallCount -= 1
        lock.unlock()
    }

    private func key(service: String, account: String) -> String {
        "\(service)\u{0}\(account)"
    }
}

struct KeychainStoreTests {
    @Test func securityBackendKeepsReadControlsOutOfMutationQueries() {
        let mutationQuery = PlexSecurityKeychainBackend.itemIdentityQuery(
            service: "tests.keychain-query",
            account: "credential"
        )
        let readQuery = PlexSecurityKeychainBackend.readQuery(
            service: "tests.keychain-query",
            account: "credential"
        )

        #expect(mutationQuery[kSecMatchLimit as String] == nil)
        #expect(mutationQuery[kSecReturnData as String] == nil)
        #expect(readQuery.keys.contains(kSecMatchLimit as String))
        #expect(readQuery[kSecReturnData as String] as? Bool == true)
    }

    @Test func concurrentStoresCompleteThroughTheSharedAccessLane() async throws {
        let runID = UUID().uuidString
        let backend = TestKeychainBackend()
        let accessLane = PlexKeychainAccessLane(backend: backend)
        let stores = (0..<32).map { index in
            KeychainStore(
                service: "tests.keychain-lane.\(runID).\(index)",
                accessLane: accessLane
            )
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, store) in stores.enumerated() {
                group.addTask {
                    try await store.write("value-\(index)", account: "credential")
                }
            }
            try await group.waitForAll()
        }

        let values = try await withThrowingTaskGroup(
            of: (Int, String?).self,
            returning: [Int: String?].self
        ) { group in
            for (index, store) in stores.enumerated() {
                group.addTask {
                    (index, try await store.read(account: "credential"))
                }
            }

            var collected: [Int: String?] = [:]
            for try await (index, value) in group {
                collected[index] = value
            }
            return collected
        }

        for index in stores.indices {
            #expect(values[index] == "value-\(index)")
        }
        #expect(backend.maximumActiveCallCount == 1)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for store in stores {
                group.addTask {
                    try await store.delete(account: "credential")
                }
            }
            try await group.waitForAll()
        }
    }
}
