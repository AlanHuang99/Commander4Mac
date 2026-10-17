// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation
@preconcurrency import Citadel
@preconcurrency import NIOSSH
@preconcurrency import NIOCore
@preconcurrency import NIOPosix
import CryptoKit
import Logging

/// Citadel 0.12.1's existing-channel entry point synchronously installs NIO
/// handlers. Its nonisolated async work must run on that channel's event loop.
private final class SSHHandshakeExecutor: TaskExecutor {
    let loop: any EventLoop
    init(_ loop: any EventLoop) { self.loop = loop }
    func enqueue(_ job: consuming ExecutorJob) {
        let unowned = UnownedJob(job)
        loop.execute { [self] in unowned.runSynchronously(on: asUnownedTaskExecutor()) }
    }
}

private final class StrictHostValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    let profile: ConnectionProfile
    private let lock = NSLock()
    private var rejected: HostKeyChallenge?
    init(_ profile: ConnectionProfile) { self.profile = profile }
    var challenge: HostKeyChallenge? { lock.withLock { rejected } }
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        do {
            try HostKeyVerification.verify(profile: profile, observed: String(openSSHPublicKey: hostKey))
            validationCompletePromise.succeed(())
        } catch {
            if let challenge = error as? HostKeyChallenge { lock.withLock { rejected = challenge } }
            validationCompletePromise.fail(error)
        }
    }
}

public actor SFTPConnectionManager: RemoteFileAccess {
    private struct Session { let client: SSHClient; let channel: any Channel; let profile: ConnectionProfile; let token: UUID }
    private struct PendingChannel { let attempt: UUID; let channel: any Channel }
    private var pendingChannels: [UUID: PendingChannel] = [:]
    private var sessions: [UUID: Session] = [:]
    private var endpointSnapshots: [UUID: RemoteEndpointSnapshot] = [:]
    public func endpointSnapshot(_ location: FileLocation) -> RemoteEndpointSnapshot? {
        guard let id = location.profileID, let snapshot = endpointSnapshots[id], snapshot.protocolKind == location.connectionProtocol else { return nil }; return snapshot
    }
    private var identities = ConnectionIdentityGuard()
    private var attempts: [UUID: UUID] = [:]
    private var states: [UUID: SFTPConnectionState] = [:]
    private var observers: [UUID: AsyncStream<[UUID: SFTPConnectionState]>.Continuation] = [:]
    private let operationTimeout: Duration
    public init(operationTimeout: Duration = .seconds(30)) { self.operationTimeout = operationTimeout }
    public func state(_ id: UUID) -> SFTPConnectionState { states[id] ?? .disconnected }
    public func snapshots() -> AsyncStream<[UUID: SFTPConnectionState]> {
        let id = UUID(); let (stream, continuation) = AsyncStream<[UUID: SFTPConnectionState]>.makeStream(bufferingPolicy: .bufferingNewest(1))
        observers[id] = continuation; continuation.yield(states)
        continuation.onTermination = { [weak self] _ in Task { await self?.removeObserver(id) } }
        return stream
    }
    private func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
    private func setState(_ state: SFTPConnectionState, id: UUID) { states[id] = state; for observer in observers.values { observer.yield(states) } }
    private static var quietLogger: Logger { var logger = Logger(label: "Commander4Mac.SFTP"); logger.logLevel = .critical; return logger }
    public func isConnected(_ id: UUID) -> Bool { sessions[id]?.client.isConnected == true }
    public func connect(_ rawProfile: ConnectionProfile, secret: String, attempt: UUID = UUID()) async throws {
        try await withTaskCancellationHandler {
            try await connectTransport(rawProfile, secret: secret, attempt: attempt)
        } onCancel: { Task { await self.cancelAttempt(attempt) } }
    }
    public func cancelAttempt(_ attempt: UUID) async {
        let ids = attempts.filter { $0.value == attempt }.map(\.key)
        for id in ids where attempts[id] == attempt { await disconnect(id) }
    }
    private func connectTransport(_ rawProfile: ConnectionProfile, secret: String, attempt: UUID) async throws {
        try Task.checkCancellation()
        let profile = try rawProfile.validated()
        guard profile.protocolKind == .sftp else { throw FileOperationError.message("This provider requires an SFTP profile.") }
        try identities.bind(profile); endpointSnapshots[profile.id] = .init(profile: profile)
        if let existing = sessions[profile.id], existing.profile.hasSameCredentialScope(as: profile) && existing.client.isConnected { setState(.connected, id: profile.id); return }
        await disconnect(profile.id)
        try Task.checkCancellation()
        attempts[profile.id] = attempt; setState(.connecting, id: profile.id)
        let validator = StrictHostValidator(profile)
        var openedChannel: (any Channel)?
        do {
            let auth: SSHAuthenticationMethod
            switch profile.authentication {
            case .guest: throw FileOperationError.message("Guest authentication is unavailable for SFTP.")
            case .password: auth = .passwordBased(username: profile.username, password: secret)
            case .ed25519Key:
                guard let reference = profile.keyReference else { throw FileOperationError.message("Choose a private key.") }
                let keyData = try await BlockingFileWorker.run { try LocalKeyMaterial.read(reference) }
                auth = try .ed25519(username: profile.username, privateKey: Curve25519.Signing.PrivateKey(sshEd25519: keyData,
                    decryptionKey: secret.isEmpty ? nil : Data(secret.utf8)))
            }
            try Task.checkCancellation()
            guard attempts[profile.id] == attempt else { throw CancellationError() }
            // Own TCP lifetime: Citadel's host convenience API leaves failed-handshake
            // channels open. Its settings overload awaits authentication on our channel.
            let channel = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
                .connectTimeout(.seconds(15)).connect(host: profile.host, port: profile.port).get()
            openedChannel = channel
            try Task.checkCancellation()
            guard attempts[profile.id] == attempt else { throw CancellationError() }
            pendingChannels[profile.id] = .init(attempt: attempt, channel: channel)
            let settings = SSHClientSettings(host: profile.host, port: profile.port, authenticationMethod: { auth }, hostKeyValidator: .custom(validator))
            let client = try await withTaskExecutorPreference(SSHHandshakeExecutor(channel.eventLoop)) {
                try await SSHClient.connect(on: channel, settings: settings)
            }
            try Task.checkCancellation()
            guard attempts[profile.id] == attempt else { throw CancellationError() }
            let token = UUID()
            pendingChannels.removeValue(forKey: profile.id)
            sessions[profile.id] = .init(client: client, channel: channel, profile: profile, token: token)
            channel.closeFuture.whenComplete { [weak self] _ in Task { await self?.disconnected(profile.id, token: token) } }
            setState(.connected, id: profile.id)
        } catch {
            if pendingChannels[profile.id]?.attempt == attempt { pendingChannels.removeValue(forKey: profile.id) }
            if let openedChannel { try? await openedChannel.close() }
            try Task.checkCancellation()
            guard attempts[profile.id] == attempt else { throw CancellationError() }
            if let challenge = validator.challenge { setState(.verificationRequired, id: profile.id); throw challenge }
            setState(.failed, id: profile.id)
            if error is FileOperationError { throw error }
            throw FileOperationError.message("SFTP connection failed. Check the host, credentials, and network access. \(String(describing: type(of: error)))")
        }
    }
    private func disconnected(_ id: UUID, token: UUID) {
        guard sessions[id]?.token == token else { return }
        sessions.removeValue(forKey: id); setState(.disconnected, id: id)
    }
    public func disconnect(_ id: UUID) async {
        attempts.removeValue(forKey: id); setState(.disconnected, id: id)
        if let pending = pendingChannels.removeValue(forKey: id) { try? await pending.channel.close() }
        if let session = sessions.removeValue(forKey: id) { try? await session.channel.close() }
    }
    private func session(_ location: FileLocation) throws -> Session {
        guard let id = location.profileID, let session = sessions[id], session.client.isConnected else {
            throw FileOperationError.message("This SFTP connection is disconnected. Open it from Connections to reconnect.")
        }
        return session
    }
    private func timer(for location: FileLocation, token: UUID) -> Task<Void, Never> {
        let timeout = operationTimeout
        return Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            await self?.expire(location.profileID, token: token)
        }
    }
    private func expire(_ id: UUID?, token: UUID) async {
        guard let id, sessions[id]?.token == token else { return }
        await disconnect(id)
    }
    public func list(_ location: FileLocation, options: ListingOptions) async throws -> DirectorySnapshot {
        try await list(location, options: options, limit: 100_000)
    }
    public func list(_ location: FileLocation, options: ListingOptions, limit: Int) async throws -> DirectorySnapshot {
        let session = try session(location); let deadline = timer(for: location, token: session.token); defer { deadline.cancel() }
        let token = session.token
        do {
        return try await withTaskCancellationHandler {
        try Task.checkCancellation()
        return try await session.client.withSFTP(logger: Self.quietLogger) { sftp in
            let groups = try await sftp.listDirectory(atPath: location.remotePath!.rawValue, maxEntries: limit)
            var entries: [FileEntry] = []
            for component in groups.flatMap(\.components) {
                let name = component.filename
                if name == "." || name == ".." { continue }
                let child = try location.appending(name)
                if !options.includeHidden && name.hasPrefix(".") { continue }
                let metadata = Self.metadata(component.attributes)
                entries.append(.init(location: child, name: name, kind: metadata.kind,
                    byteSize: metadata.kind == .directory ? nil : metadata.size.flatMap(Int64.init(exactly:)), modificationDate: metadata.modified, placeholderState: .unknown))
            }
            guard Set(entries.map(\.id)).count == entries.count else { throw FileOperationError.message("The server returned duplicate directory entries.") }
            return .init(location: location, entries: entries)
        }
        } onCancel: { Task { await self.expire(location.profileID, token: token) } }
        } catch { throw sftpError(error) }
    }
    private nonisolated static func metadata(_ attributes: SFTPFileAttributes) -> RemoteFileMetadata {
        .init(size: attributes.size, permissions: attributes.permissions, modified: attributes.accessModificationTime?.modificationTime)
    }
    public func metadata(_ location: FileLocation) async throws -> RemoteFileMetadata? {
        let session = try session(location); let deadline = timer(for: location, token: session.token); defer { deadline.cancel() }
        // Direct LSTAT retains symlink type without rereading the parent directory.
        let token = session.token
        do {
        return try await withTaskCancellationHandler {
        try Task.checkCancellation()
        return try await session.client.withSFTP(logger: Self.quietLogger) { sftp in
            do { return Self.metadata(try await sftp.getAttributes(at: location.remotePath!.rawValue, followSymlinks: false)) }
            catch let status as SFTPMessage.Status where status.errorCode == .noSuchFile { return nil }
        }
        } onCancel: { Task { await self.expire(location.profileID, token: token) } }
        } catch { throw sftpError(error) }
    }
    public func openFile(_ location: FileLocation, writeExclusive: Bool) async throws -> any RemoteFileChannel {
        let session = try session(location); let token = session.token
        let deadline = timer(for: location, token: token); defer { deadline.cancel() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let sftp = try await session.client.openSFTP(logger: Self.quietLogger)
            do {
                var attributes = SFTPFileAttributes.none
                if writeExclusive { attributes.permissions = 0o600 }
                let file = try await sftp.openFile(filePath: location.remotePath!.rawValue,
                    flags: writeExclusive ? [.write, .create, .forceCreate] : .read, attributes: attributes)
                return CitadelFileChannel(file: file, client: sftp, timeout: operationTimeout,
                    hardAbort: { [weak self] in await self?.expire(location.profileID, token: token) })
            } catch { try? await sftp.close(); throw sftpError(error) }
        } onCancel: { Task { await self.expire(location.profileID, token: token) } }
    }
    public func rename(_ source: FileLocation, to destination: FileLocation) async throws {
        guard source.profileID == destination.profileID else { throw FileOperationError.message("Rename requires the same server.") }
        let session = try session(source); let deadline = timer(for: source, token: session.token); defer { deadline.cancel() }
        let token = session.token
        do {
        try await withTaskCancellationHandler {
        try Task.checkCancellation()
        try await session.client.withSFTP(logger: Self.quietLogger) { sftp in
            try await sftp.rename(at: source.remotePath!.rawValue, to: destination.remotePath!.rawValue)
        }
        } onCancel: { Task { await self.expire(source.profileID, token: token) } }
        } catch { throw sftpError(error) }
    }
    public func createDirectory(_ location: FileLocation) async throws {
        let session = try session(location); let deadline = timer(for: location, token: session.token); defer { deadline.cancel() }
        let token = session.token
        do {
        try await withTaskCancellationHandler {
        try Task.checkCancellation()
        try await session.client.withSFTP(logger: Self.quietLogger) { sftp in
            try await sftp.createDirectory(atPath: location.remotePath!.rawValue)
        }
        } onCancel: { Task { await self.expire(location.profileID, token: token) } }
        } catch { throw sftpError(error) }
    }
}

private actor CitadelFileChannel: RemoteFileChannel {
    private let file: SFTPFile
    private let client: SFTPClient
    private var closed = false
    private let timeout: Duration
    private let hardAbort: @Sendable () async -> Void
    init(file: SFTPFile, client: SFTPClient, timeout: Duration, hardAbort: @escaping @Sendable () async -> Void) {
        self.file = file; self.client = client; self.timeout = timeout; self.hardAbort = hardAbort
    }
    private func deadline() -> Task<Void, Never> {
        let timeout = timeout
        return Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            await self?.abort()
        }
    }
    func read(offset: UInt64, length: UInt32) async throws -> Data {
        guard !closed else { throw FileOperationError.message("The SFTP file channel is closed.") }
        let timeout = deadline(); defer { timeout.cancel() }
        do {
            return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let bytes = try await file.read(from: offset, length: min(length, 65536))
            guard bytes.readableBytes <= 65536 else { throw FileOperationError.message("The server returned an oversized SFTP chunk.") }
            return Data(bytes.readableBytesView)
            } onCancel: { Task { await self.abort() } }
        } catch { throw sftpError(error) }
    }
    func write(_ data: Data, offset: UInt64) async throws {
        guard !closed, data.count <= 65536 else { throw FileOperationError.message("Invalid SFTP write chunk.") }
        let timeout = deadline(); defer { timeout.cancel() }
        do {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await file.write(ByteBuffer(bytes: data), at: offset)
            } onCancel: { Task { await self.abort() } }
        } catch { throw sftpError(error) }
    }
    func close() async throws {
        guard !closed else { return }; closed = true
        let timeout = deadline(); defer { timeout.cancel() }
        do {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await file.close(); try await client.close()
            } onCancel: { Task { await self.abort() } }
        } catch { await abort(); throw error }
    }
    func abort() async {
        closed = true
        // SSH child close waits for the peer. Closing the owned parent TCP
        // transport fails pending requests even when that peer is unresponsive.
        await hardAbort()
    }
}

private func sftpError(_ error: Error) -> any Error {
    if case SFTPError.directoryListingLimitExceeded(let limit) = error { return FileOperationError.message("Directory entry limit exceeded (\(limit)).") }
    guard let status = error as? SFTPMessage.Status else { return error }
    let message: String
    switch status.errorCode {
    case .permissionDenied: message = "The SFTP server denied access. Check permissions on the server for this location."
    case .noSuchFile: message = "The remote item is unavailable or no longer exists. Refresh the folder."
    case .failure: message = "The SFTP server rejected this operation. Check the destination name, permissions, and available storage."
    default: message = "The SFTP request failed (server status \(status.errorCode.rawValue))."
    }
    return FileOperationError.message(message)
}
