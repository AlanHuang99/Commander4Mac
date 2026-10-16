import Foundation

public protocol ConnectionProfilePersisting: Sendable {
    func save(_ profiles: [ConnectionProfile]) throws
}
extension ConnectionStore: ConnectionProfilePersisting {}

/// Stage credential updates with rollback. Delete previous credentials only
/// after the atomic profile document commits. Cleanup warnings do not undo a
/// committed document or leave the in-memory profile list out of sync with it.
public struct ConnectionProfileCommit: Sendable {
    private let store: any ConnectionProfilePersisting
    private let vault: CredentialVault
    public init(store: any ConnectionProfilePersisting, vault: CredentialVault) { self.store = store; self.vault = vault }
    public func save(profiles: [ConnectionProfile], previous: ConnectionProfile?, prepared: ConnectionProfile,
                     secret: String?, remember: Bool, allowCredentialTransfer: Bool) throws -> String? {
        let backup = try vault.record(for: prepared)
        let transferred = try previous.flatMap { old -> String? in
            guard allowCredentialTransfer, old.hasSameCredentialScope(as: prepared) else { return nil }
            return try vault.read(for: old)
        }
        var staged = false
        do {
            if remember, let value = secret ?? transferred, !value.isEmpty {
                try vault.write(value, for: prepared); staged = true
            }
            try store.save(profiles)
        } catch {
            if staged {
                do { try vault.restore(backup, for: prepared) }
                catch { throw FileOperationError.message("Connections were not saved, and Keychain rollback failed. Review this connection's credential in Keychain Access before retrying.") }
            }
            throw error
        }
        do {
            if let previous, previous.id != prepared.id { try vault.remove(for: previous) }
            if !remember { try vault.remove(for: prepared) }
            return nil
        } catch { return "Connection saved, but an unused credential could not be removed. Review this app's SFTP items in Keychain Access." }
    }
    public func remove(profiles: [ConnectionProfile], removed: ConnectionProfile) throws -> String? {
        try store.save(profiles)
        do { try vault.remove(for: removed); return nil }
        catch { return "Connection removed, but its unused credential remains in Keychain. Remove this app's SFTP item in Keychain Access." }
    }
}
