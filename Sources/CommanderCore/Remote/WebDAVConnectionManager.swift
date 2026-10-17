// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation

public actor WebDAVConnectionManager: RemoteFileAccess {
    private struct Session: Sendable { let endpoint: WebDAVEndpoint; let transport: WebDAVHTTPTransport }
    private var sessions: [UUID: Session] = [:]; private var pending: [UUID: (UUID, Session)] = [:]
    private var endpointSnapshots: [UUID: RemoteEndpointSnapshot] = [:]
    public func endpointSnapshot(_ location: FileLocation) -> RemoteEndpointSnapshot? {
        guard let id = location.profileID, let snapshot = endpointSnapshots[id], snapshot.protocolKind == location.connectionProtocol else { return nil }; return snapshot
    }
    private var identities = ConnectionIdentityGuard()
    public init() {}
    public func connect(_ raw: ConnectionProfile, secret: String, attempt: UUID = UUID()) async throws {
        let profile = try raw.validated(); guard profile.protocolKind == .webdav else { throw WebDAVEndpoint.invalid() }
        try identities.bind(profile); endpointSnapshots[profile.id] = .init(profile: profile); try Task.checkCancellation()
        if sessions[profile.id] != nil { return }
        let session = Session(endpoint: try WebDAVEndpoint(profile: profile), transport: WebDAVHTTPTransport(profile: profile, secret: secret))
        if let old = pending.removeValue(forKey: profile.id) { old.1.transport.close() }
        pending[profile.id] = (attempt, session)
        do {
            let root = FileLocation.webdav(profileID: profile.id, path: try RemotePath("/"))
            guard try await properties(root, depth: 0, session: session)?.metadata?.kind == .directory else { throw FileOperationError.message("The WebDAV base collection is unavailable.") }
            try Task.checkCancellation()
            guard pending[profile.id]?.0 == attempt else { throw CancellationError() }
            pending.removeValue(forKey: profile.id); sessions.removeValue(forKey: profile.id)?.transport.close(); sessions[profile.id] = session
        } catch { if pending[profile.id]?.0 == attempt { pending.removeValue(forKey: profile.id) }; session.transport.close(); throw error }
    }
    public func cancelAttempt(_ attempt: UUID) { for (id, value) in pending where value.0 == attempt { pending.removeValue(forKey: id)?.1.transport.close() } }
    public func disconnect(_ id: UUID) { sessions.removeValue(forKey: id)?.transport.close(); pending.removeValue(forKey: id)?.1.transport.close() }
    public func isConnected(_ id: UUID) -> Bool { sessions[id] != nil }
    private func session(_ location: FileLocation) throws -> Session {
        guard location.connectionProtocol == .webdav, let id = location.profileID, let session = sessions[id] else { throw FileOperationError.message("This WebDAV connection is disconnected. Open it from Connections.") }; return session
    }
    private func properties(_ location: FileLocation, depth: Int, session: Session) async throws -> WebDAVListing? {
        var request = URLRequest(url: try session.endpoint.url(location.remotePath!, collection: depth == 1)); request.httpMethod = "PROPFIND"
        request.setValue(String(depth), forHTTPHeaderField: "Depth"); request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("<?xml version=\"1.0\" encoding=\"utf-8\"?><d:propfind xmlns:d=\"DAV:\"><d:prop><d:resourcetype/><d:getcontentlength/><d:getlastmodified/><d:getetag/></d:prop></d:propfind>".utf8)
        let result = try await session.transport.send(request)
        if result.response.statusCode == 404 { return nil }
        try Self.require(result, status: 207)
        let data = try await BlockingFileWorker.run { try Data(contentsOf: result.spool.file) }
        return try WebDAVListing.parse(data, endpoint: session.endpoint, location: location, depth: depth)
    }
    public func list(_ location: FileLocation, options: ListingOptions) async throws -> DirectorySnapshot {
        guard let value = try await properties(location, depth: 1, session: session(location)), value.metadata?.kind == .directory else { throw FileOperationError.message("The WebDAV folder is unavailable.") }
        return .init(location: location, entries: value.entries.filter { options.includeHidden || !$0.name.hasPrefix(".") })
    }
    public func list(_ location: FileLocation, options: ListingOptions, limit: Int) async throws -> DirectorySnapshot {
        let snapshot = try await list(location, options: options)
        guard snapshot.entries.count <= limit else { throw FileOperationError.message("Directory entry limit exceeded.") }; return snapshot
    }
    public func metadata(_ location: FileLocation) async throws -> RemoteFileMetadata? { try await properties(location, depth: 0, session: session(location))?.metadata }
    public func openFile(_ location: FileLocation, writeExclusive: Bool) async throws -> any RemoteFileChannel {
        let current = try session(location)
        if writeExclusive { return try DAVWriteChannel(location: location, endpoint: current.endpoint, transport: current.transport) }
        guard let metadata = try await metadata(location), metadata.isRegularFile, let size = metadata.size else { throw FileOperationError.message("WebDAV file size is unavailable.") }
        var request = URLRequest(url: try current.endpoint.url(location.remotePath!)); request.httpMethod = "GET"
        if let tag = metadata.revision { request.setValue(tag, forHTTPHeaderField: "If-Match") }
        let result = try await current.transport.send(request, limit: max(size, 8192))
        try Self.require(result, status: 200)
        guard UInt64(try ItemVersion.read(at: result.spool.file).size) == size else { throw FileOperationError.message("The WebDAV file changed while downloading.") }
        return try DAVReadChannel(spool: result.spool)
    }
    public func rename(_ source: FileLocation, to destination: FileLocation) async throws {
        guard source.providerID == destination.providerID else { throw WebDAVEndpoint.invalid() }
        let current = try session(source)
        var request = URLRequest(url: try current.endpoint.url(source.remotePath!)); request.httpMethod = "MOVE"
        request.setValue(try current.endpoint.url(destination.remotePath!).absoluteString, forHTTPHeaderField: "Destination"); request.setValue("F", forHTTPHeaderField: "Overwrite")
        try Self.require(try await current.transport.send(request), status: 201)
    }
    public func createDirectory(_ location: FileLocation) async throws {
        let current = try session(location); var request = URLRequest(url: try current.endpoint.url(location.remotePath!, collection: true)); request.httpMethod = "MKCOL"
        try Self.require(try await current.transport.send(request), status: 201)
    }
    static func require(_ response: DAVHTTPResponse, status: Int) throws {
        guard response.response.statusCode == status else {
            let code = response.response.statusCode
            let detail = (300..<400).contains(code) ? "Redirects are not followed. Save the final WebDAV endpoint in the connection." : (code == 401 || code == 403 ? "Authentication or access was denied." : "The server did not confirm the operation.")
            throw FileOperationError.message("WebDAV HTTP \(code). \(detail)")
        }
    }
}
