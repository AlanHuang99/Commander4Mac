import Foundation
@preconcurrency import SMB2
import Darwin

/// Each profile owns one serialized C context. Network operations run on bounded
/// workers; cancellation shuts down its owned socket to interrupt blocked I/O.
final class SMBSession: @unchecked Sendable {
    private let lock = NSLock()
    private let stateLock = NSLock()
    private var aborted = false
    private var socket: Int32?
    let context: UnsafeMutablePointer<smb2_context>
    init() throws {
        guard let context = smb2_init_context() else { throw FileOperationError.message("Could not create SMB session.") }
        self.context = context; smb2_set_timeout(context, 30)
    }
    deinit { if let socket { Darwin.close(socket) }; smb2_destroy_context(context) }
    func abort() {
        stateLock.withLock { aborted = true; if let socket { _ = shutdown(socket, SHUT_RDWR) } }
    }
    var connected: Bool { stateLock.withLock { !aborted && socket != nil } }
    func activateSocket() throws {
        let descriptor = fcntl(smb2_get_fd(context), F_DUPFD_CLOEXEC, 0)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        try stateLock.withLock {
            guard !aborted else { _ = shutdown(descriptor, SHUT_RDWR); Darwin.close(descriptor); throw CancellationError() }
            socket = descriptor
        }
    }
    func run<T: Sendable>(_ operation: @escaping @Sendable (UnsafeMutablePointer<smb2_context>) throws -> T) async throws -> T {
        do {
            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await BlockingFileWorker.run { [self] in
                    try lock.withLock { guard !stateLock.withLock({ aborted }) else { throw CancellationError() }; return try operation(context) }
                }
            } onCancel: { self.abort() }
        } catch {
            let value = error as NSError
            if value.domain == NSPOSIXErrorDomain && [ECONNRESET, ENOTCONN, ETIMEDOUT, EPIPE, EIO].contains(Int32(value.code)) { abort() }
            throw error
        }
    }
    static func check(_ code: Int32) throws { guard code >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(-code)) } }
    static func error(_ context: UnsafeMutablePointer<smb2_context>) -> NSError {
        let code = nterror_to_errno(UInt32(bitPattern: smb2_get_nterror(context)))
        return NSError(domain: NSPOSIXErrorDomain, code: Int(code > 0 ? code : EIO))
    }
    static func metadata(_ value: smb2_stat_64) -> RemoteFileMetadata {
        let mode = value.smb2_type == SMB2_TYPE_DIRECTORY ? S_IFDIR : (value.smb2_type == SMB2_TYPE_LINK ? S_IFLNK : S_IFREG)
        return .init(size: value.smb2_size, permissions: UInt32(mode), modified: Date(timeIntervalSince1970: Double(value.smb2_mtime) + Double(value.smb2_mtime_nsec) / 1_000_000_000))
    }
    static func path(_ location: FileLocation) throws -> String {
        guard location.connectionProtocol == .smb, let path = location.remotePath else { throw FileOperationError.message("This action requires a connected SMB location.") }
        for component in path.rawValue.split(separator: "/") {
            _ = try FileNameRules.validateComponent(String(component))
            guard !component.contains("\\"), !component.contains(":") else { throw FileOperationError.message("SMB backslash and alternate-stream paths are not supported.") }
        }
        return String(path.rawValue.dropFirst())
    }
}
public actor SMBConnectionManager: RemoteFileAccess {
    private var sessions: [UUID: SMBSession] = [:]
    private var attempts: [UUID: UUID] = [:]
    private var pending: [UUID: SMBSession] = [:]
    private var endpointSnapshots: [UUID: RemoteEndpointSnapshot] = [:]
    public func endpointSnapshot(_ location: FileLocation) -> RemoteEndpointSnapshot? {
        guard let id = location.profileID, let snapshot = endpointSnapshots[id], snapshot.protocolKind == location.connectionProtocol else { return nil }; return snapshot
    }
    private var identities = ConnectionIdentityGuard()
    public init() {}
    public func connect(_ raw: ConnectionProfile, secret: String, attempt: UUID = UUID()) async throws {
        let profile = try raw.validated(); try identities.bind(profile); endpointSnapshots[profile.id] = .init(profile: profile)
        guard profile.protocolKind == .smb else { throw FileOperationError.message("This provider requires SMB.") }
        if sessions[profile.id]?.connected == true { return }
        await disconnect(profile.id); try Task.checkCancellation()
        let session = try SMBSession(); pending[profile.id] = session; attempts[profile.id] = attempt
        do {
            try await session.run { context in
                smb2_set_user(context, profile.authentication == .guest ? "" : profile.username)
                smb2_set_password(context, secret); smb2_set_domain(context, profile.domain)
                if profile.authentication != .guest { smb2_set_security_mode(context, UInt16(SMB2_NEGOTIATE_SIGNING_REQUIRED)) }
                try SMBSession.check(smb2_connect_share(context, profile.host + ":" + String(profile.port), profile.share, profile.authentication == .guest ? "" : profile.username))
                try session.activateSocket()
            }
            guard attempts[profile.id] == attempt, !Task.isCancelled else { session.abort(); throw CancellationError() }
            pending.removeValue(forKey: profile.id); sessions[profile.id] = session
        } catch { if attempts[profile.id] == attempt { pending.removeValue(forKey: profile.id) }; session.abort(); throw error }
    }
    public func cancelAttempt(_ attempt: UUID) async {
        for id in attempts.filter({ $0.value == attempt }).map(\.key) { await disconnect(id) }
    }
    public func disconnect(_ id: UUID) async {
        attempts.removeValue(forKey: id); pending.removeValue(forKey: id)?.abort(); sessions.removeValue(forKey: id)?.abort()
    }
    public func isConnected(_ id: UUID) -> Bool { sessions[id]?.connected == true }
    private func session(_ location: FileLocation) throws -> SMBSession {
        guard location.connectionProtocol == .smb, let id = location.profileID, let session = sessions[id], session.connected else { throw FileOperationError.message("This SMB share is disconnected. Open it from Connections.") }
        return session
    }
    public func list(_ location: FileLocation, options: ListingOptions) async throws -> DirectorySnapshot {
        let session = try session(location); let path = try SMBSession.path(location)
        return try await session.run { context in
            guard let directory = smb2_opendir(context, path) else { throw SMBSession.error(context) }
            defer { smb2_closedir(context, directory) }
            var entries: [FileEntry] = []
            while let item = smb2_readdir(context, directory) {
                guard let namePointer = item.pointee.name else { throw FileOperationError.message("SMB returned a missing name.") }
                let name = String(cString: namePointer)
                if name == "." || name == ".." { continue }
                let child = try location.appending(name); _ = try SMBSession.path(child)
                if !options.includeHidden && name.hasPrefix(".") { continue }
                let metadata = SMBSession.metadata(item.pointee.st)
                entries.append(.init(location: child, name: name, kind: metadata.kind,
                    byteSize: metadata.kind == .directory ? nil : metadata.size.flatMap(Int64.init(exactly:)), modificationDate: metadata.modified, placeholderState: .unknown))
                guard entries.count <= 100_000 else { throw FileOperationError.message("The SMB directory exceeds 100,000 items.") }
            }
            guard Set(entries.map(\.id)).count == entries.count else { throw FileOperationError.message("SMB returned duplicate names.") }
            return .init(location: location, entries: entries)
        }
    }
    public func metadata(_ location: FileLocation) async throws -> RemoteFileMetadata? {
        let session = try session(location); let path = try SMBSession.path(location)
        return try await session.run { context in
            var value = smb2_stat_64(); let code = smb2_stat(context, path, &value)
            if code == -ENOENT { return nil }; try SMBSession.check(code); return SMBSession.metadata(value)
        }
    }
    public func openFile(_ location: FileLocation, writeExclusive: Bool) async throws -> any RemoteFileChannel {
        let session = try session(location); let path = try SMBSession.path(location)
        let file = try await session.run { context in
            guard let file = smb2_open(context, path, writeExclusive ? O_WRONLY | O_CREAT | O_EXCL : O_RDONLY) else { throw SMBSession.error(context) }
            return SMBFileHandle(file)
        }
        return SMBFileChannel(session: session, file: file, writable: writeExclusive)
    }
    public func rename(_ source: FileLocation, to destination: FileLocation) async throws {
        guard source.providerID == destination.providerID else { throw FileOperationError.message("Rename requires the same share.") }
        let session = try session(source); let from = try SMBSession.path(source); let to = try SMBSession.path(destination)
        // Pinned libsmb2's rename encodes replace_if_exist = 0.
        try await session.run { try SMBSession.check(smb2_rename($0, from, to)) }
    }
    public func createDirectory(_ location: FileLocation) async throws {
        let session = try session(location); let path = try SMBSession.path(location)
        try await session.run { try SMBSession.check(smb2_mkdir($0, path)) }
    }
}
private struct SMBFileHandle: @unchecked Sendable { let pointer: OpaquePointer; init(_ pointer: OpaquePointer) { self.pointer = pointer } }
private actor SMBFileChannel: RemoteFileChannel {
    let session: SMBSession
    let file: SMBFileHandle
    let writable: Bool
    private var closed = false
    init(session: SMBSession, file: SMBFileHandle, writable: Bool) { self.session = session; self.file = file; self.writable = writable }
    func read(offset: UInt64, length: UInt32) async throws -> Data {
        guard !closed, !writable else { throw FileOperationError.message("SMB channel is not readable.") }
        let file = file
        return try await session.run { context in
            var data = Data(count: Int(min(length, 65536)))
            let count = data.withUnsafeMutableBytes { smb2_pread(context, file.pointer, $0.baseAddress!.assumingMemoryBound(to: UInt8.self), UInt32($0.count), offset) }
            try SMBSession.check(count); guard count <= data.count else { throw FileOperationError.message("SMB returned an oversized read.") }; return Data(data.prefix(Int(count)))
        }
    }
    func write(_ data: Data, offset: UInt64) async throws {
        guard !closed, writable, data.count <= 65536 else { throw FileOperationError.message("Invalid SMB write.") }
        let file = file
        try await session.run { context in
            let count = data.withUnsafeBytes { smb2_pwrite(context, file.pointer, $0.baseAddress!.assumingMemoryBound(to: UInt8.self), UInt32($0.count), offset) }
            try SMBSession.check(count); guard count == data.count else { throw FileOperationError.message("SMB accepted only part of the write.") }
        }
    }
    func close() async throws {
        guard !closed else { return }; closed = true
        let file = file; let writable = writable
        try await session.run { context in
            var error: (any Error)?
            if writable { do { try SMBSession.check(smb2_fsync(context, file.pointer)) } catch let e { error = e } }
            let code = smb2_close(context, file.pointer); if let error { throw error }; try SMBSession.check(code)
        }
    }
}
