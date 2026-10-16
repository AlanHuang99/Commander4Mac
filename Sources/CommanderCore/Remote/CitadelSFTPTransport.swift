import Foundation
@preconcurrency import Citadel
@preconcurrency import NIOSSH
@preconcurrency import NIOCore
import CryptoKit
import Logging

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
    private struct Session { let client: SSHClient; let profile: ConnectionProfile; let token: UUID }
    private var sessions: [UUID: Session] = [:]
    private var attempts: [UUID: UUID] = [:]
    public init() {}
    private static var quietLogger: Logger { var logger = Logger(label: "Commander4Mac.SFTP"); logger.logLevel = .critical; return logger }
    public func isConnected(_ id: UUID) -> Bool { sessions[id]?.client.isConnected == true }
    public func connect(_ rawProfile: ConnectionProfile, secret: String) async throws {
        let profile = try rawProfile.validated()
        if let existing = sessions[profile.id], existing.profile == profile && existing.client.isConnected { return }
        await disconnect(profile.id)
        let attempt = UUID(); attempts[profile.id] = attempt
        let validator = StrictHostValidator(profile)
        let auth: SSHAuthenticationMethod
        switch profile.authentication {
        case .password: auth = .passwordBased(username: profile.username, password: secret)
        case .ed25519Key:
            guard let reference = profile.keyReference else { throw FileOperationError.message("Choose a private key.") }
            let keyData = try await BlockingFileWorker.run {
                guard case .available(let location) = LocationResolver().resolve(reference) else { throw FileOperationError.message("The saved private key is unavailable. Choose it again.") }
                let data = try Data(contentsOf: location.url)
                guard data.count <= 1_048_576 else { throw FileOperationError.message("The private key file is too large.") }
                return data
            }
            auth = try .ed25519(username: profile.username, privateKey: Curve25519.Signing.PrivateKey(sshEd25519: keyData,
                decryptionKey: secret.isEmpty ? nil : Data(secret.utf8)))
        }
        do {
            let client = try await SSHClient.connect(host: profile.host, port: profile.port, authenticationMethod: auth,
                hostKeyValidator: .custom(validator), reconnect: .never, connectTimeout: .seconds(15))
            guard attempts[profile.id] == attempt else { try? await client.close(); throw CancellationError() }
            sessions[profile.id] = .init(client: client, profile: profile, token: UUID())
        } catch {
            if let challenge = validator.challenge { throw challenge }
            throw FileOperationError.message("SFTP connection failed. Check the host, credentials, and network access. \(String(describing: type(of: error)))")
        }
    }
    public func disconnect(_ id: UUID) async {
        attempts.removeValue(forKey: id)
        if let session = sessions.removeValue(forKey: id) { try? await session.client.close() }
    }
    private func session(_ location: FileLocation) throws -> Session {
        guard let id = location.profileID, let session = sessions[id], session.client.isConnected else {
            throw FileOperationError.message("This SFTP connection is disconnected. Open it from Connections to reconnect.")
        }
        return session
    }
    private func timer(for location: FileLocation, token: UUID) -> Task<Void, Never> {
        Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            await self?.expire(location.profileID, token: token)
        }
    }
    private func expire(_ id: UUID?, token: UUID) async {
        guard let id, sessions[id]?.token == token else { return }
        await disconnect(id)
    }
    public func list(_ location: FileLocation, options: ListingOptions) async throws -> DirectorySnapshot {
        let session = try session(location); let deadline = timer(for: location, token: session.token); defer { deadline.cancel() }
        return try await session.client.withSFTP(logger: Self.quietLogger) { sftp in
            let groups = try await sftp.listDirectory(atPath: location.remotePath!.rawValue)
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
    }
    private nonisolated static func metadata(_ attributes: SFTPFileAttributes) -> RemoteFileMetadata {
        .init(size: attributes.size, permissions: attributes.permissions, modified: attributes.accessModificationTime?.modificationTime)
    }
    public func metadata(_ location: FileLocation) async throws -> RemoteFileMetadata? {
        let session = try session(location); let deadline = timer(for: location, token: session.token); defer { deadline.cancel() }
        // READDIR retains symlink type, unlike STAT, which follows it.
        return try await session.client.withSFTP(logger: Self.quietLogger) { sftp in
            if location.remotePath!.rawValue == "/" { return Self.metadata(try await sftp.getAttributes(at: "/")) }
            let groups = try await sftp.listDirectory(atPath: location.parent.remotePath!.rawValue)
            let matches = groups.flatMap(\.components).filter { $0.filename == location.url.lastPathComponent }
            guard matches.count <= 1 else { throw FileOperationError.message("The server returned an ambiguous filename.") }
            return matches.first.map { Self.metadata($0.attributes) }
        }
    }
    public func openFile(_ location: FileLocation, writeExclusive: Bool) async throws -> any RemoteFileChannel {
        let session = try session(location); let deadline = timer(for: location, token: session.token); defer { deadline.cancel() }
        let sftp = try await session.client.openSFTP(logger: Self.quietLogger)
        do {
            var attributes = SFTPFileAttributes.none
            if writeExclusive { attributes.permissions = 0o600 }
            let file = try await sftp.openFile(filePath: location.remotePath!.rawValue,
                flags: writeExclusive ? [.write, .create, .forceCreate] : .read, attributes: attributes)
            return CitadelFileChannel(file: file, client: sftp)
        } catch { try? await sftp.close(); throw error }
    }
    public func rename(_ source: FileLocation, to destination: FileLocation) async throws {
        guard source.profileID == destination.profileID else { throw FileOperationError.message("Rename requires the same server.") }
        let session = try session(source); let deadline = timer(for: source, token: session.token); defer { deadline.cancel() }
        try await session.client.withSFTP(logger: Self.quietLogger) { sftp in
            try await sftp.rename(at: source.remotePath!.rawValue, to: destination.remotePath!.rawValue)
        }
    }
    public func createDirectory(_ location: FileLocation) async throws {
        let session = try session(location); let deadline = timer(for: location, token: session.token); defer { deadline.cancel() }
        try await session.client.withSFTP(logger: Self.quietLogger) { sftp in
            try await sftp.createDirectory(atPath: location.remotePath!.rawValue)
        }
    }
}

private actor CitadelFileChannel: RemoteFileChannel {
    private let file: SFTPFile
    private let client: SFTPClient
    private var closed = false
    init(file: SFTPFile, client: SFTPClient) { self.file = file; self.client = client }
    private func deadline() -> Task<Void, Never> {
        Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            try? await self?.abort()
        }
    }
    func read(offset: UInt64, length: UInt32) async throws -> Data {
        guard !closed else { throw FileOperationError.message("The SFTP file channel is closed.") }
        let timeout = deadline(); defer { timeout.cancel() }
        let bytes = try await file.read(from: offset, length: min(length, 65536))
        return Data(bytes.readableBytesView)
    }
    func write(_ data: Data, offset: UInt64) async throws {
        guard !closed, data.count <= 65536 else { throw FileOperationError.message("Invalid SFTP write chunk.") }
        let timeout = deadline(); defer { timeout.cancel() }
        try await file.write(ByteBuffer(bytes: data), at: offset)
    }
    func close() async throws {
        guard !closed else { return }; closed = true
        let timeout = deadline(); defer { timeout.cancel() }
        do { try await file.close(); try await client.close() }
        catch { try? await client.close(); throw error }
    }
    private func abort() async throws {
        closed = true
        try await client.close()
    }
}
