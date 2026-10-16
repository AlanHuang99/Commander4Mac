import Foundation
import Observation
import CommanderCore

@MainActor @Observable final class ConnectionController {
    private(set) var profiles: [ConnectionProfile]
    private(set) var states: [UUID: SFTPConnectionState] = [:]
    var diagnostic: String?
    private let store: ConnectionStore
    private let vault: CredentialVault
    private let remote: SFTPConnectionManager
    private let edits = OperationGate()
    private var knownIDs: Set<UUID>
    private var observation: Task<Void, Never>?
    init(remote: SFTPConnectionManager, directory: URL) {
        self.remote = remote; store = ConnectionStore(directory: directory)
        vault = CredentialVault(store: KeychainSecretStore(service: (Bundle.main.bundleIdentifier ?? "Commander4Mac") + ".SFTP"))
        let loaded = store.load(); profiles = loaded.profiles; diagnostic = loaded.diagnostic; knownIDs = Set(loaded.profiles.map(\.id))
        observation = Task { [weak self, remote] in
            for await states in await remote.snapshots() { self?.states = states }
        }
    }
    isolated deinit { observation?.cancel() }
    func secret(for profile: ConnectionProfile) async throws -> String? {
        let vault = vault
        return try await BlockingFileWorker.run { try vault.read(for: profile) }
    }
    func save(_ candidate: ConnectionProfile, secret: String?, remember: Bool, allowHostKeyChange: Bool = false) async throws -> ConnectionProfile {
        await edits.acquire()
        do {
            let previous = profiles.first { $0.id == candidate.id }
            guard previous != nil || !knownIDs.contains(candidate.id) else { throw FileOperationError.message("This connection changed or was removed. Reopen its editor before saving.") }
            var candidate = candidate
            if !allowHostKeyChange, let previous, previous.host.lowercased() == candidate.host.lowercased(), previous.port == candidate.port { candidate.serverKey = previous.serverKey }
            let prepared = try ConnectionProfileChange.prepare(candidate, previous: previous)
            var updated = profiles
            if let index = updated.firstIndex(where: { $0.id == candidate.id }) { updated[index] = prepared } else { updated.append(prepared) }
            let captured = updated; let vault = vault; let store = store
            try await BlockingFileWorker.run {
                // Moving an existing secret to a new identity is allowed only for an
                // explicitly re-trusted host key at the same credential scope.
                let transferred = try previous.flatMap { old -> String? in
                    guard allowHostKeyChange, old.hasSameCredentialScope(as: prepared) else { return nil }
                    return try vault.read(for: old)
                }
                if let previous, previous.id != prepared.id { try vault.remove(for: previous) }
                if !remember { try vault.remove(for: prepared) }
                if remember, let value = secret ?? transferred, !value.isEmpty { try vault.write(value, for: prepared) }
                try store.save(captured)
            }
            profiles = updated; knownIDs.insert(prepared.id)
            if let previous, previous.id != prepared.id { await remote.disconnect(previous.id) }
            await edits.release(); return prepared
        } catch { await edits.release(); throw error }
    }
    func trust(_ key: String, for profile: ConnectionProfile) async throws -> ConnectionProfile {
        var trusted = profile; trusted.serverKey = HostKeyVerification.normalized(key)
        return try await save(trusted, secret: nil, remember: true, allowHostKeyChange: true)
    }
    func remove(_ profile: ConnectionProfile) async throws {
        await edits.acquire()
        do {
            let updated = profiles.filter { $0.id != profile.id }; let store = store; let vault = vault
            try await BlockingFileWorker.run { try vault.remove(for: profile); try store.save(updated) }
            profiles = updated; await remote.disconnect(profile.id); await edits.release()
        } catch { await edits.release(); throw error }
    }
}
