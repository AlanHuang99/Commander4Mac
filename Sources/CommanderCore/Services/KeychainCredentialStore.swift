// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation
import Security

public protocol SecretStore: Sendable {
    func read(account: String) throws -> Data?
    func write(_ data: Data, account: String) throws
    func remove(account: String) throws
}
public struct KeychainSecretStore: SecretStore {
    private let service: String
    public init(service: String) { self.service = service }
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    public func read(account: String) throws -> Data? {
        var q = query(account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status); return result as? Data
    }
    public func write(_ data: Data, account: String) throws {
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(account); q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            try check(SecItemAdd(q as CFDictionary, nil))
        } else { try check(status) }
    }
    public func remove(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw FileOperationError.message("Keychain could not access this connection's credential (\(status)).") }
    }
}
public struct CredentialVault: Sendable {
    private struct Record: Codable { let scope: String; let secret: String }
    private let store: any SecretStore
    public init(store: any SecretStore) { self.store = store }
    public func read(for profile: ConnectionProfile) throws -> String? {
        guard let data = try store.read(account: profile.id.uuidString) else { return nil }
        let record = try JSONDecoder().decode(Record.self, from: data)
        return record.scope.utf8.elementsEqual(profile.credentialScope.utf8) ? record.secret : nil
    }
    public func write(_ secret: String, for profile: ConnectionProfile) throws {
        try store.write(JSONEncoder().encode(Record(scope: profile.credentialScope, secret: secret)), account: profile.id.uuidString)
    }
    public func remove(for profile: ConnectionProfile) throws { try store.remove(account: profile.id.uuidString) }
    func record(for profile: ConnectionProfile) throws -> Data? { try store.read(account: profile.id.uuidString) }
    func restore(_ data: Data?, for profile: ConnectionProfile) throws {
        if let data { try store.write(data, account: profile.id.uuidString) }
        else { try store.remove(account: profile.id.uuidString) }
    }
}
