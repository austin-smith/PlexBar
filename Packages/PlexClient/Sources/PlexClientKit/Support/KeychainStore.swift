import PlexModels
import Foundation
import Security

public enum PlexKeychainOperation: String, Sendable {
    case read
    case update
    case add
    case delete
}

public struct PlexKeychainError: Error, Equatable, LocalizedError, Sendable {
    public let operation: PlexKeychainOperation
    public let status: OSStatus

    public var errorDescription: String? {
        let systemDescription = SecCopyErrorMessageString(status, nil) as String?
        let detail = systemDescription?.nilIfBlank ?? "Security framework status \(status)"
        return "Keychain \(operation.rawValue) failed. \(detail)"
    }

    public init(operation: PlexKeychainOperation, status: OSStatus) {
        self.operation = operation
        self.status = status
    }
}

public protocol PlexKeychainBackend: Sendable {
    func read(service: String, account: String) throws -> String?
    func write(_ value: String, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

public struct PlexSecurityKeychainBackend: PlexKeychainBackend {
    public func read(service: String, account: String) throws -> String? {
        let query = Self.readQuery(service: service, account: account)

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw PlexKeychainError(operation: .read, status: status)
        }
        guard let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw PlexKeychainError(operation: .read, status: errSecDecode)
        }

        return string
    }

    public func write(_ value: String, service: String, account: String) throws {
        let data = Data(value.utf8)
        let query = Self.itemIdentityQuery(service: service, account: account)
        let attributes = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw PlexKeychainError(operation: .update, status: updateStatus)
        }

        var createQuery = query
        createQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(createQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw PlexKeychainError(operation: .add, status: addStatus)
        }
    }

    public func delete(service: String, account: String) throws {
        let status = SecItemDelete(
            Self.itemIdentityQuery(service: service, account: account) as CFDictionary
        )
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PlexKeychainError(operation: .delete, status: status)
        }
    }

    public static func itemIdentityQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    public static func readQuery(service: String, account: String) -> [String: Any] {
        var query = itemIdentityQuery(service: service, account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        return query
    }

    public init() {}

}

public actor PlexKeychainAccessLane {
    public static let shared = PlexKeychainAccessLane()

    private let backend: any PlexKeychainBackend

    public init(backend: any PlexKeychainBackend = PlexSecurityKeychainBackend()) {
        self.backend = backend
    }

    public func read(service: String, account: String) throws -> String? {
        try backend.read(service: service, account: account)
    }

    public func write(_ value: String, service: String, account: String) throws {
        try backend.write(value, service: service, account: account)
    }

    public func delete(service: String, account: String) throws {
        try backend.delete(service: service, account: account)
    }
}

public struct KeychainStore: Sendable {
    public let service: String
    private let accessLane: PlexKeychainAccessLane

    public init(service: String, accessLane: PlexKeychainAccessLane = .shared) {
        self.service = service
        self.accessLane = accessLane
    }

    public func read(account: String) async throws -> String? {
        try await accessLane.read(service: service, account: account)
    }

    public func write(_ value: String, account: String) async throws {
        try await accessLane.write(value, service: service, account: account)
    }

    public func delete(account: String) async throws {
        try await accessLane.delete(service: service, account: account)
    }
}

public struct PlexStoredCredentials: Equatable, Sendable {
    public let userToken: String
    public let serverToken: String

    public static let empty = PlexStoredCredentials(userToken: "", serverToken: "")

    public init(userToken: String, serverToken: String) {
        self.userToken = userToken
        self.serverToken = serverToken
    }
}

public protocol PlexCredentialPersisting: Actor {
    func loadCredentials() async throws -> PlexStoredCredentials
    func replace(_ value: String?, account: String) async throws
}

public actor PlexKeychainCredentialStore: PlexCredentialPersisting {
    private let keychain: KeychainStore

    public init(keychain: KeychainStore) {
        self.keychain = keychain
    }

    public func loadCredentials() async throws -> PlexStoredCredentials {
        async let userToken = keychain.read(account: KeychainAccounts.userToken)
        async let serverToken = keychain.read(account: KeychainAccounts.serverToken)
        let credentials = try await (userToken, serverToken)

        return PlexStoredCredentials(
            userToken: credentials.0 ?? "",
            serverToken: credentials.1 ?? ""
        )
    }

    public func replace(_ value: String?, account: String) async throws {
        guard let value = value?.nilIfBlank else {
            try await keychain.delete(account: account)
            return
        }

        try await keychain.write(value, account: account)
    }
}

public actor PlexMemoryCredentialStore: PlexCredentialPersisting {
    private var values: [String: String]

    public init(credentials: PlexStoredCredentials = .empty) {
        values = [
            KeychainAccounts.userToken: credentials.userToken,
            KeychainAccounts.serverToken: credentials.serverToken
        ]
    }

    public func loadCredentials() async -> PlexStoredCredentials {
        PlexStoredCredentials(
            userToken: values[KeychainAccounts.userToken] ?? "",
            serverToken: values[KeychainAccounts.serverToken] ?? ""
        )
    }

    public func replace(_ value: String?, account: String) async {
        values[account] = value?.nilIfBlank
    }
}
