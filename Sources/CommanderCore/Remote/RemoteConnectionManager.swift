import Foundation

public actor RemoteConnectionManager: RemoteFileAccess {
    private let sftp = SFTPConnectionManager()
    private let smb = SMBConnectionManager()
    private let webdav = WebDAVConnectionManager()
    private var kinds: [UUID: ConnectionProtocol] = [:]
    private var endpointSnapshots: [UUID: RemoteEndpointSnapshot] = [:]
    public func endpointSnapshot(_ location: FileLocation) -> RemoteEndpointSnapshot? {
        guard let id = location.profileID, let snapshot = endpointSnapshots[id], snapshot.protocolKind == location.connectionProtocol else { return nil }; return snapshot
    }
    private var identities = ConnectionIdentityGuard()
    private var states: [UUID: SFTPConnectionState] = [:]
    private var observers: [UUID: AsyncStream<[UUID: SFTPConnectionState]>.Continuation] = [:]
    private var sftpObservation: Task<Void, Never>?
    public init() {}
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
    private func mergeSFTP(_ values: [UUID: SFTPConnectionState]) {
        for (id, value) in values where kinds[id] == .sftp { states[id] = value }; publish()
    }
    private func publish() { for observer in observers.values { observer.yield(states) } }
    private func setState(_ state: SFTPConnectionState, id: UUID) { states[id] = state; publish() }
    public func connect(_ raw: ConnectionProfile, secret: String, attempt: UUID = UUID()) async throws {
        let profile = try raw.validated(); try identities.bind(profile); endpointSnapshots[profile.id] = .init(profile: profile); try Task.checkCancellation()
        kinds[profile.id] = profile.protocolKind; setState(.connecting, id: profile.id)
        do {
            switch profile.protocolKind {
            case .sftp: try await sftp.connect(profile, secret: secret, attempt: attempt)
            case .smb: try await smb.connect(profile, secret: secret, attempt: attempt)
            case .webdav: try await webdav.connect(profile, secret: secret, attempt: attempt)
            }
            try Task.checkCancellation(); setState(.connected, id: profile.id)
        } catch { setState(error is HostKeyChallenge ? .verificationRequired : (error is CancellationError ? .disconnected : .failed), id: profile.id); throw error }
    }
    public func disconnect(_ id: UUID) async {
        switch kinds[id] { case .sftp: await sftp.disconnect(id); case .smb: await smb.disconnect(id); case .webdav: await webdav.disconnect(id); default: break }
        setState(.disconnected, id: id)
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
    public func list(_ location: FileLocation, options: ListingOptions) async throws -> DirectorySnapshot {
        do { return try await provider(location).list(location, options: options) }
        catch { if let id = location.profileID, !(await isConnected(id)) { setState(.disconnected, id: id) }; throw error }
    }
    public func list(_ location: FileLocation, options: ListingOptions, limit: Int) async throws -> DirectorySnapshot {
        do { return try await provider(location).list(location, options: options, limit: limit) }
        catch { if let id = location.profileID, !(await isConnected(id)) { setState(.disconnected, id: id) }; throw error }
    }
    public func metadata(_ location: FileLocation) async throws -> RemoteFileMetadata? { try await provider(location).metadata(location) }
    public func openFile(_ location: FileLocation, writeExclusive: Bool) async throws -> any RemoteFileChannel { try await provider(location).openFile(location, writeExclusive: writeExclusive) }
    public func rename(_ source: FileLocation, to destination: FileLocation) async throws { try await provider(source).rename(source, to: destination) }
    public func createDirectory(_ location: FileLocation) async throws { try await provider(location).createDirectory(location) }
}
