import Foundation
import Security

public protocol CredentialStore: Sendable {
    func token(for serverId: UUID) -> String?
    func setToken(_ token: String, for serverId: UUID) throws
    func removeToken(for serverId: UUID)
}

public enum CredentialStoreError: Error, Equatable {
    case keychain(OSStatus)
}

public struct KeychainCredentialStore: CredentialStore {
    public let service: String

    public init(service: String = "io.github.malkafen.boltun.session") {
        self.service = service
    }

    private func baseQuery(_ serverId: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serverId.uuidString,
        ]
    }

    public func token(for serverId: UUID) -> String? {
        var query = baseQuery(serverId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setToken(_ token: String, for serverId: UUID) throws {
        let data = Data(token.utf8)
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(baseQuery(serverId) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(serverId)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CredentialStoreError.keychain(status) }
    }

    public func removeToken(for serverId: UUID) {
        SecItemDelete(baseQuery(serverId) as CFDictionary)
    }
}

public final class MemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [UUID: String]

    public init(_ tokens: [UUID: String] = [:]) {
        self.tokens = tokens
    }

    public func token(for serverId: UUID) -> String? {
        lock.withLock { tokens[serverId] }
    }

    public func setToken(_ token: String, for serverId: UUID) throws {
        lock.withLock { tokens[serverId] = token }
    }

    public func removeToken(for serverId: UUID) {
        lock.withLock { _ = tokens.removeValue(forKey: serverId) }
    }
}
