// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation

actor DAVReadChannel: RemoteFileChannel {
    private let spool: DAVSpool; private var handle: FileHandle?
    init(spool: DAVSpool) throws { self.spool = spool; handle = try FileHandle(forReadingFrom: spool.file) }
    func read(offset: UInt64, length: UInt32) async throws -> Data {
        try Task.checkCancellation(); guard let handle, length <= 65536 else { throw FileOperationError.message("The WebDAV read channel is closed or the block is too large.") }
        return try await BlockingFileWorker.run { try handle.seek(toOffset: offset); return try handle.read(upToCount: Int(length)) ?? Data() }
    }
    func write(_ data: Data, offset: UInt64) async throws { throw FileOperationError.message("This WebDAV channel is read-only.") }
    func close() async throws { let value = handle; handle = nil; try value?.close() }
}
actor DAVWriteChannel: RemoteFileChannel {
    private let spool: DAVSpool; private var handle: FileHandle?; private var offset: UInt64 = 0
    private let location: FileLocation; private let endpoint: WebDAVEndpoint; private let transport: WebDAVHTTPTransport
    init(location: FileLocation, endpoint: WebDAVEndpoint, transport: WebDAVHTTPTransport) throws {
        self.location = location; self.endpoint = endpoint; self.transport = transport; spool = try DAVSpool(); handle = try FileHandle(forWritingTo: spool.file)
    }
    func read(offset: UInt64, length: UInt32) async throws -> Data { throw FileOperationError.message("This WebDAV channel is write-only.") }
    func write(_ data: Data, offset: UInt64) async throws {
        try Task.checkCancellation(); guard let handle, offset == self.offset, data.count <= 65536 else { throw FileOperationError.message("The WebDAV write channel is closed or out of sequence.") }
        try await BlockingFileWorker.run { try handle.write(contentsOf: data) }; self.offset += UInt64(data.count)
    }
    func close() async throws {
        guard let value = handle else { return }; handle = nil
        try await BlockingFileWorker.run { try value.synchronize(); try value.close() }; try Task.checkCancellation()
        var request = URLRequest(url: try endpoint.url(location.remotePath!)); request.httpMethod = "PUT"
        request.setValue("*", forHTTPHeaderField: "If-None-Match"); request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        try WebDAVConnectionManager.require(try await transport.send(request, upload: spool.file), status: 201)
    }
    func abort() async { let value = handle; handle = nil; try? value?.close() }
}
