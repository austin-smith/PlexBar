import PlexModels
import Foundation
import Security

enum PlexKeychainOperation: String, Sendable {
    case read
    case update
    case add
    case delete
}

struct PlexKeychainError: Error, Equatable, LocalizedError, Sendable {
    let operation: PlexKeychainOperation
    let status: OSStatus

    var errorDescription: String? {
        let systemDescription = SecCopyErrorMessageString(status, nil) as String?
        let detail = systemDescription?.nilIfBlank ?? "Security framework status \(status)"
        return "Keychain \(operation.rawValue) failed. \(detail)"
    }
}

protocol PlexKeychainBackend: Sendable {
    func read(service: String, account: String) throws -> String?
    func write(_ value: String, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

struct PlexSecurityKeychainBackend: PlexKeychainBackend {
    func read(service: String, account: String) throws -> String? {
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

    func write(_ value: String, service: String, account: String) throws {
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

    func delete(service: String, account: String) throws {
        let status = SecItemDelete(
            Self.itemIdentityQuery(service: service, account: account) as CFDictionary
        )
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PlexKeychainError(operation: .delete, status: status)
        }
    }

    static func itemIdentityQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func readQuery(service: String, account: String) -> [String: Any] {
        var query = itemIdentityQuery(service: service, account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        return query
    }
}

actor PlexKeychainAccessLane {
    static let shared = PlexKeychainAccessLane()

    private let backend: any PlexKeychainBackend

    init(backend: any PlexKeychainBackend = PlexSecurityKeychainBackend()) {
        self.backend = backend
    }

    func read(service: String, account: String) throws -> String? {
        try backend.read(service: service, account: account)
    }

    func write(_ value: String, service: String, account: String) throws {
        try backend.write(value, service: service, account: account)
    }

    func delete(service: String, account: String) throws {
        try backend.delete(service: service, account: account)
    }
}

struct KeychainStore: Sendable {
    let service: String
    private let accessLane: PlexKeychainAccessLane

    init(
        service: String,
        accessLane: PlexKeychainAccessLane = .shared
    ) {
        self.service = service
        self.accessLane = accessLane
    }

    func read(account: String) async throws -> String? {
        try await accessLane.read(service: service, account: account)
    }

    func write(_ value: String, account: String) async throws {
        try await accessLane.write(value, service: service, account: account)
    }

    func delete(account: String) async throws {
        try await accessLane.delete(service: service, account: account)
    }
}

struct PlexStoredCredentials: Equatable, Sendable {
    let userToken: String
    let serverToken: String

    static let empty = PlexStoredCredentials(userToken: "", serverToken: "")
}

protocol PlexCredentialPersisting: Actor {
    func loadCredentials() async throws -> PlexStoredCredentials
    func replace(_ value: String?, account: String) async throws
}

actor PlexKeychainCredentialStore: PlexCredentialPersisting {
    private let keychain: KeychainStore

    init(keychain: KeychainStore) {
        self.keychain = keychain
    }

    func loadCredentials() async throws -> PlexStoredCredentials {
        async let userToken = keychain.read(account: KeychainAccounts.userToken)
        async let serverToken = keychain.read(account: KeychainAccounts.serverToken)
        let credentials = try await (userToken, serverToken)

        return PlexStoredCredentials(
            userToken: credentials.0 ?? "",
            serverToken: credentials.1 ?? ""
        )
    }

    func replace(_ value: String?, account: String) async throws {
        guard let value = value?.nilIfBlank else {
            try await keychain.delete(account: account)
            return
        }

        try await keychain.write(value, account: account)
    }
}

actor PlexMemoryCredentialStore: PlexCredentialPersisting {
    private var values: [String: String]

    init(credentials: PlexStoredCredentials = .empty) {
        values = [
            KeychainAccounts.userToken: credentials.userToken,
            KeychainAccounts.serverToken: credentials.serverToken
        ]
    }

    func loadCredentials() async -> PlexStoredCredentials {
        PlexStoredCredentials(
            userToken: values[KeychainAccounts.userToken] ?? "",
            serverToken: values[KeychainAccounts.serverToken] ?? ""
        )
    }

    func replace(_ value: String?, account: String) async {
        values[account] = value?.nilIfBlank
    }
}
