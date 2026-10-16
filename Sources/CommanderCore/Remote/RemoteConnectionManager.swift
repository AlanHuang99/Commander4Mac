import Foundation

public actor RemoteConnectionManager: RemoteFileAccess {
    private let sftp: any RemoteConnectionTransport
    private let smb: any RemoteConnectionTransport
    private let webdav: any RemoteConnectionTransport
    private var kinds: [UUID: ConnectionProtocol] = [:]
    private var endpointSnapshots: [UUID: RemoteEndpointSnapshot] = [:]
    public func endpointSnapshot(_ location: FileLocation) -> RemoteEndpointSnapshot? {
        guard let id = location.profileID, let snapshot = endpointSnapshots[id], snapshot.protocolKind == location.connectionProtocol else { return nil }; return snapshot
    }
    private var identities = ConnectionIdentityGuard()
    private var generations: [UUID: UUID] = [:]
    private var pendingAttempts: [UUID: UUID] = [:]
    private var deferredSFTPLoss: [UUID: UUID] = [:]
    private var states: [UUID: SFTPConnectionState] = [:]
    private var observers: [UUID: AsyncStream<[UUID: SFTPConnectionState]>.Continuation] = [:]
    private var sftpObservation: Task<Void, Never>?
    public init() { sftp = SFTPConnectionManager(); smb = SMBConnectionManager(); webdav = WebDAVConnectionManager() }
    init(sftp: any RemoteConnectionTransport, smb: any RemoteConnectionTransport, webdav: any RemoteConnectionTransport) {
        self.sftp = sftp; self.smb = smb; self.webdav = webdav
    }
    deinit { sftpObservation?.cancel() }
    public func snapshots() -> AsyncStream<[UUID: SFTPConnectionState]> {
        if sftpObservation == nil {
            let source = sftp
            sftpObservation = Task { [weak self] in for await values in await source.snapshots() { await self?.mergeSFTP(values) } }
        }
        let id = UUID(); let (stream, continuation) = AsyncStream<[UUID: SFTPConnectionState]>.makeStream(bufferingPolicy: .bufferingNewest(1))
        observers[id] = continuation; continuation.yield(states)
        continuation.onTermination = { [weak self] _ in Task { await self?.removeObserver(id) } }; return stream
    }
    private func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
    private func mergeSFTP(_ values: [UUID: SFTPConnectionState]) async {
        // Connect outcomes belong to the router generation. Remember losses
        // during setup so an actor hop cannot discard the final transport event.
        for (id, value) in values where kinds[id] == .sftp && value == .disconnected {
            guard let generation = generations[id] else { continue }
            if pendingAttempts[id] != nil { deferredSFTPLoss[id] = generation; continue }
            guard states[id] == .connected else { continue }
            let connected = await sftp.isConnected(id)
            if generations[id] == generation && pendingAttempts[id] == nil && !connected { setState(.disconnected, id: id) }
        }
    }
    private func publish() { for observer in observers.values { observer.yield(states) } }
    private func setState(_ state: SFTPConnectionState, id: UUID) { states[id] = state; publish() }
    public func connect(_ raw: ConnectionProfile, secret: String, attempt: UUID = UUID()) async throws {
        let profile = try raw.validated(); try identities.bind(profile); endpointSnapshots[profile.id] = .init(profile: profile); try Task.checkCancellation()
        let generation = UUID(); generations[profile.id] = generation; pendingAttempts[profile.id] = attempt
        deferredSFTPLoss.removeValue(forKey: profile.id)
        kinds[profile.id] = profile.protocolKind; setState(.connecting, id: profile.id)
        do {
            switch profile.protocolKind {
            case .sftp: try await sftp.connect(profile, secret: secret, attempt: attempt)
            case .smb: try await smb.connect(profile, secret: secret, attempt: attempt)
            case .webdav: try await webdav.connect(profile, secret: secret, attempt: attempt)
            }
            try Task.checkCancellation()
            guard generations[profile.id] == generation else { throw CancellationError() }
            var connected = await isConnected(profile.id)
            guard generations[profile.id] == generation else { throw CancellationError() }
            while deferredSFTPLoss[profile.id] == generation {
                deferredSFTPLoss.removeValue(forKey: profile.id)
                connected = await isConnected(profile.id)
                guard generations[profile.id] == generation else { throw CancellationError() }
            }
            try Task.checkCancellation()
            guard connected else { throw FileOperationError.message("The connection closed before it was ready. Reconnect to try again.") }
            pendingAttempts.removeValue(forKey: profile.id); setState(.connected, id: profile.id)
        } catch {
            if generations[profile.id] == generation {
                pendingAttempts.removeValue(forKey: profile.id)
                deferredSFTPLoss.removeValue(forKey: profile.id)
                setState(error is HostKeyChallenge ? .verificationRequired : (error is CancellationError ? .disconnected : .failed), id: profile.id)
            }
            throw error
        }
    }
    public func disconnect(_ id: UUID) async {
        let generation = UUID(); generations[id] = generation; pendingAttempts.removeValue(forKey: id)
        deferredSFTPLoss.removeValue(forKey: id)
        switch kinds[id] { case .sftp: await sftp.disconnect(id); case .smb: await smb.disconnect(id); case .webdav: await webdav.disconnect(id); default: break }
        if generations[id] == generation { setState(.disconnected, id: id) }
    }
    public func disconnectAll() async { for id in Array(kinds.keys) { await disconnect(id) } }
    public func cancelAttempt(_ id: UUID) async { await sftp.cancelAttempt(id); await smb.cancelAttempt(id); await webdav.cancelAttempt(id) }
    public func isConnected(_ id: UUID) async -> Bool {
        switch kinds[id] { case .sftp: return await sftp.isConnected(id); case .smb: return await smb.isConnected(id); case .webdav: return await webdav.isConnected(id); default: return false }
    }
    private func provider(_ location: FileLocation) throws -> any RemoteFileAccess {
        guard let id = location.profileID, kinds[id] == location.connectionProtocol else { throw FileOperationError.message("This connection is disconnected. Open it from Connections.") }
        switch location.connectionProtocol { case .sftp: return sftp; case .smb: return smb; case .webdav: return webdav; default: throw FileOperationError.message("This remote protocol is unavailable.") }
    }
    private func retireUnavailable(_ location: FileLocation) async {
        guard let id = location.profileID, states[id] == .connected, pendingAttempts[id] == nil else { return }
        let generation = generations[id]; let connected = await isConnected(id)
        if generations[id] == generation && pendingAttempts[id] == nil && states[id] == .connected && !connected { setState(.disconnected, id: id) }
    }
    private func perform<T: Sendable>(_ location: FileLocation, operation: @Sendable (any RemoteFileAccess) async throws -> T) async throws -> T {
        do { return try await operation(provider(location)) }
        catch { await retireUnavailable(location); throw error }
    }
    public func list(_ location: FileLocation, options: ListingOptions) async throws -> DirectorySnapshot {
        try await perform(location) { try await $0.list(location, options: options) }
    }
    public func list(_ location: FileLocation, options: ListingOptions, limit: Int) async throws -> DirectorySnapshot {
        try await perform(location) { try await $0.list(location, options: options, limit: limit) }
    }
    public func metadata(_ location: FileLocation) async throws -> RemoteFileMetadata? {
        try await perform(location) { try await $0.metadata(location) }
    }
    public func openFile(_ location: FileLocation, writeExclusive: Bool) async throws -> any RemoteFileChannel {
        let channel = try await perform(location) { try await $0.openFile(location, writeExclusive: writeExclusive) }
        return ObservedRemoteFileChannel(channel: channel, retired: { [weak self] in await self?.retireUnavailable(location) })
    }
    public func rename(_ source: FileLocation, to destination: FileLocation) async throws {
        try await perform(source) { try await $0.rename(source, to: destination) }
    }
    public func createDirectory(_ location: FileLocation) async throws {
        try await perform(location) { try await $0.createDirectory(location) }
    }

}

protocol RemoteConnectionTransport: RemoteFileAccess {
    func connect(_ profile: ConnectionProfile, secret: String, attempt: UUID) async throws
    func disconnect(_ id: UUID) async
    func cancelAttempt(_ attempt: UUID) async
    func isConnected(_ id: UUID) async -> Bool
    func snapshots() async -> AsyncStream<[UUID: SFTPConnectionState]>
}
extension RemoteConnectionTransport {
    func snapshots() async -> AsyncStream<[UUID: SFTPConnectionState]> { AsyncStream { $0.finish() } }
}
extension SFTPConnectionManager: RemoteConnectionTransport {}
extension SMBConnectionManager: RemoteConnectionTransport {}
extension WebDAVConnectionManager: RemoteConnectionTransport {}

private struct ObservedRemoteFileChannel: RemoteFileChannel {
    let channel: any RemoteFileChannel
    let retired: @Sendable () async -> Void
    private func perform<T: Sendable>(_ operation: () async throws -> T) async throws -> T {
        do { return try await operation() } catch { await retired(); throw error }
    }
    func read(offset: UInt64, length: UInt32) async throws -> Data { try await perform { try await channel.read(offset: offset, length: length) } }
    func write(_ data: Data, offset: UInt64) async throws { try await perform { try await channel.write(data, offset: offset) } }
    func close() async throws { try await perform { try await channel.close() } }
    func abort() async { await channel.abort(); await retired() }
}
