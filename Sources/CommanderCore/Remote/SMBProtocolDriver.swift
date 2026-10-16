import Foundation
@preconcurrency import SMB2
@preconcurrency import SMB2.Raw
import Darwin

final class SMBAsyncReply: @unchecked Sendable {
    enum Kind { case empty, fileID, directory }
    let kind: Kind; var status: Int32?; var bytes = Data(); var failure: (any Error)?
    init(_ kind: Kind) { self.kind = kind }
    func check() throws {
        if let failure { throw failure }; guard let status else { throw FileOperationError.message("SMB did not complete the request.") }
        guard status == 0 else {
            let code = status < 0 && status >= -4096 ? -status : nterror_to_errno(UInt32(bitPattern: status))
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code > 0 ? code : EIO))
        }
    }
}
private func smbAsyncCallback(_ context: UnsafeMutablePointer<smb2_context>?, _ status: Int32, _ data: UnsafeMutableRawPointer?, _ privateData: UnsafeMutableRawPointer?) {
    guard let privateData else { return }
    let reply = Unmanaged<SMBAsyncReply>.fromOpaque(privateData).takeRetainedValue(); reply.status = status
    guard status == 0 else { return }
    switch reply.kind {
    case .empty: break
    case .fileID:
        guard let data else { reply.failure = FileOperationError.message("SMB returned no directory handle."); return }
        var id = data.assumingMemoryBound(to: smb2_create_reply.self).pointee.file_id
        reply.bytes = withUnsafeBytes(of: &id) { Data($0) }
    case .directory:
        guard let data else { reply.failure = FileOperationError.message("SMB returned no directory page."); return }
        let page = data.assumingMemoryBound(to: smb2_query_directory_reply.self).pointee
        guard page.output_buffer_length <= 65_536, let buffer = page.output_buffer else { reply.failure = FileOperationError.message("SMB returned an oversized directory page."); return }
        reply.bytes = Data(bytes: buffer, count: Int(page.output_buffer_length))
    }
}

enum SMBProtocolDriver {
    static func connect(_ session: SMBSession, profile: ConnectionProfile, secret: String) throws {
        let context = session.context
        smb2_set_user(context, profile.authentication == .guest ? "" : profile.username); smb2_set_password(context, secret); smb2_set_domain(context, profile.domain)
        if profile.authentication != .guest { smb2_set_security_mode(context, UInt16(SMB2_NEGOTIATE_SIGNING_REQUIRED)) }
        let reply = SMBAsyncReply(.empty); let retained = Unmanaged.passRetained(reply).toOpaque()
        let host = profile.host.contains(":") ? "[\(profile.host)]:\(profile.port)" : profile.host + ":" + String(profile.port)
        let status = smb2_connect_share_async(context, host, profile.share, profile.authentication == .guest ? "" : profile.username, smbAsyncCallback, retained)
        if status < 0 { Unmanaged<SMBAsyncReply>.fromOpaque(retained).release(); try SMBSession.check(status) }
        try session.service(reply); try reply.check(); try session.activateSocket()
    }
    private static func command(_ session: SMBSession, kind: SMBAsyncReply.Kind, deadline: TimeInterval, make: (smb2_command_cb, UnsafeMutableRawPointer) -> UnsafeMutablePointer<smb2_pdu>?) throws -> SMBAsyncReply {
        try session.checkActive()
        let reply = SMBAsyncReply(kind); let retained = Unmanaged.passRetained(reply).toOpaque()
        guard let pdu = make(smbAsyncCallback, retained) else { Unmanaged<SMBAsyncReply>.fromOpaque(retained).release(); throw SMBSession.error(session.context) }
        smb2_queue_pdu(session.context, pdu); try session.service(reply, deadline: deadline); return reply
    }
    static func list(_ session: SMBSession, location: FileLocation, options: ListingOptions, limit: Int) throws -> DirectorySnapshot {
        guard limit >= 0 else { throw FileOperationError.message("Directory entry limit must be nonnegative.") }
        let context = session.context; let path = try SMBSession.path(location); let deadline = ProcessInfo.processInfo.systemUptime + 30
        var create = smb2_create_request(); create.impersonation_level = UInt32(SMB2_IMPERSONATION_IMPERSONATION)
        create.desired_access = UInt32(SMB2_FILE_LIST_DIRECTORY | SMB2_FILE_READ_ATTRIBUTES); create.file_attributes = UInt32(SMB2_FILE_ATTRIBUTE_DIRECTORY)
        create.share_access = UInt32(SMB2_FILE_SHARE_READ | SMB2_FILE_SHARE_WRITE); create.create_disposition = UInt32(SMB2_FILE_OPEN); create.create_options = UInt32(SMB2_FILE_DIRECTORY_FILE)
        let opened = try path.withCString { name in
            create.name = name
            return try command(session, kind: .fileID, deadline: deadline) { smb2_cmd_create_async(context, &create, $0, $1) }
        }
        try opened.check(); let fileID = opened.bytes
        guard fileID.count == 16 else { throw FileOperationError.message("SMB returned an invalid directory handle.") }
        defer {
            var close = smb2_close_request(); _ = withUnsafeMutableBytes(of: &close.file_id) { fileID.copyBytes(to: $0) }
            if let reply = try? command(session, kind: .empty, deadline: deadline, make: { smb2_cmd_close_async(context, &close, $0, $1) }) { try? reply.check() }
        }
        var entries: [FileEntry] = []; var seen = Set<RemotePath>(); var observed = 0; var pages = 0
        while true {
            try session.checkActive(); pages += 1
            guard pages <= limit + 2 else { throw FileOperationError.message("SMB directory page limit exceeded.") }
            var query = smb2_query_directory_request(); query.file_information_class = UInt8(SMB2_FILE_ID_FULL_DIRECTORY_INFORMATION); query.output_buffer_length = 65_536
            _ = withUnsafeMutableBytes(of: &query.file_id) { fileID.copyBytes(to: $0) }
            let reply = try "*".withCString { name in query.name = name; return try command(session, kind: .directory, deadline: deadline) { smb2_cmd_query_directory_async(context, &query, $0, $1) } }
            if reply.status.map({ UInt32(bitPattern: $0) }) == UInt32(SMB2_STATUS_NO_MORE_FILES) { break }
            try reply.check(); let data = reply.bytes
            guard !data.isEmpty else { throw FileOperationError.message("SMB returned an empty directory page without completing enumeration.") }
            var offset = 0
            while true {
                try session.checkActive()
                guard data.count - offset >= 80 else { throw FileOperationError.message("SMB returned a truncated directory record.") }
                let next = Int(data.u32(offset)); let length = Int(data.u32(offset + 60))
                guard length > 0, length % 2 == 0, length <= data.count - offset - 80,
                      let name = String(data: data.subdata(in: offset + 80..<offset + 80 + length), encoding: .utf16LittleEndian) else { throw FileOperationError.message("SMB returned an invalid filename.") }
                if name != "." && name != ".." {
                    guard observed < limit else { throw FileOperationError.message("Directory entry limit exceeded.") }; observed += 1
                    let child = try location.appending(name); _ = try SMBSession.path(child)
                    guard seen.insert(child.remotePath!).inserted else { throw FileOperationError.message("SMB returned duplicate names.") }
                    if options.includeHidden || !name.hasPrefix(".") {
                        let attributes = data.u32(offset + 56)
                        let kind: FileKind = attributes & UInt32(SMB2_FILE_ATTRIBUTE_REPARSE_POINT) != 0 ? .symbolicLink : (attributes & UInt32(SMB2_FILE_ATTRIBUTE_DIRECTORY) != 0 ? .directory : .file)
                        let size = data.u64(offset + 40); let ticks = data.u64(offset + 24)
                        entries.append(.init(location: child, name: name, kind: kind, byteSize: kind == .directory ? nil : Int64(exactly: size), modificationDate: Date(timeIntervalSince1970: Double(ticks) / 10_000_000 - 11_644_473_600), placeholderState: .unknown))
                    }
                }
                if next == 0 { break }
                guard next >= 80 + length, next % 8 == 0, next <= data.count - offset - 80 else { throw FileOperationError.message("SMB returned an invalid directory record offset.") }; offset += next
            }
        }
        return .init(location: location, entries: entries)
    }
}
private extension Data {
    func u32(_ offset: Int) -> UInt32 { withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) } }
    func u64(_ offset: Int) -> UInt64 { withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self)) } }
}

/// SMB negotiation and I/O have their own bounded workers, preserving local work.
enum SMBNetworkWorker {
    private static let queue: OperationQueue = { let q = OperationQueue(); q.name = "Commander4Mac.SMB"; q.maxConcurrentOperationCount = 4; q.qualityOfService = .userInitiated; return q }()
    static func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in queue.addOperation { do { continuation.resume(returning: try work()) } catch { continuation.resume(throwing: error) } } }
    }
}
