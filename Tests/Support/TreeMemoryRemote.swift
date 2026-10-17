// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation
import CommanderCore
import Darwin

actor TreeMemoryRemote: RemoteFileAccess {
    nonisolated let root: FileLocation
    struct Node { var kind: FileKind; var bytes: Data; var revision: Int }
    private var endpoint: RemoteEndpointSnapshot?
    func setEndpoint(_ value: RemoteEndpointSnapshot) { endpoint = value }
    func endpointSnapshot(_ location: FileLocation) -> RemoteEndpointSnapshot? { endpoint }
    private var nodes: [FileLocation: Node] = [:]
    var token: OperationCancellation?; var mutate: URL?; var loseRename = false; var raceRename = false; var tamperStage = false; var failReads = false; var readCount = 0
    private(set) var mutations = 0
    init(protocolKind: ConnectionProtocol = .sftp) { root = .remote(kind: protocolKind, profileID: UUID(), path: try! RemotePath("/")); nodes[root] = .init(kind: .directory, bytes: Data(), revision: 0) }
    func configure(token: OperationCancellation? = nil, mutate: URL? = nil, loseRename: Bool = false, raceRename: Bool = false, tamperStage: Bool = false, failReads: Bool = false) { self.token = token; self.mutate = mutate; self.loseRename = loseRename; self.raceRename = raceRename; self.tamperStage = tamperStage; self.failReads = failReads }
    func seed(_ path: FileLocation, kind: FileKind = .file, bytes: Data = Data()) { nodes[path] = .init(kind: kind, bytes: bytes, revision: 0) }
    func data(_ path: FileLocation) -> Data? { nodes[path]?.bytes }
    func list(_ location: FileLocation, options: ListingOptions) async throws -> DirectorySnapshot {
        guard nodes[location]?.kind == .directory else { throw FileOperationError.message("missing directory") }
        if tamperStage && location.title.hasPrefix(".commander4mac-"), let file = nodes.first(where: { $0.key.parent == location && $0.value.kind == .file })?.key {
            tamperStage = false; nodes[file]!.bytes = Data(repeating: 122, count: nodes[file]!.bytes.count); nodes[file]!.revision += 1
        }
        return .init(location: location, entries: nodes.filter { $0.key != location && $0.key.parent == location }.map { loc, node in .init(location: loc, name: loc.title, kind: node.kind, byteSize: node.kind == .file ? Int64(node.bytes.count) : nil) })
    }
    func metadata(_ location: FileLocation) async throws -> RemoteFileMetadata? {
        nodes[location].map { node in .init(size: node.kind == .file ? UInt64(node.bytes.count) : nil, permissions: UInt32(node.kind == .directory ? S_IFDIR : (node.kind == .symbolicLink ? S_IFLNK : S_IFREG)), modified: Date(timeIntervalSince1970: Double(node.revision))) }
    }
    func openFile(_ location: FileLocation, writeExclusive: Bool) async throws -> any RemoteFileChannel {
        if writeExclusive { guard nodes[location] == nil, nodes[location.parent]?.kind == .directory else { throw FileOperationError.message("exists or missing parent") }; seed(location); mutations += 1 }
        else { guard nodes[location]?.kind == .file else { throw FileOperationError.message("missing file") } }
        return TreeMemoryChannel(server: self, location: location)
    }
    func read(_ location: FileLocation, offset: UInt64, length: UInt32) throws -> Data {
        readCount += 1; if failReads && readCount > 1 { throw FileOperationError.message("owned fixture disconnect") }
        guard let bytes = nodes[location]?.bytes else { throw FileOperationError.message("disconnected") }
        let start = min(Int(offset), bytes.count); return bytes.subdata(in: start..<min(bytes.count, start + Int(length)))
    }
    func write(_ location: FileLocation, bytes: Data, offset: UInt64) throws {
        guard nodes[location]?.bytes.count == Int(offset) else { throw FileOperationError.message("offset") }; nodes[location]!.bytes.append(bytes)
        if let mutate { try Data("changed".utf8).write(to: mutate); self.mutate = nil }
        token?.cancel()
    }
    func createDirectory(_ location: FileLocation) async throws { guard nodes[location] == nil, nodes[location.parent]?.kind == .directory else { throw FileOperationError.message("exists or parent") }; seed(location, kind: .directory); mutations += 1 }
    func rename(_ source: FileLocation, to destination: FileLocation) async throws {
        if raceRename && nodes[source]?.kind == .directory { raceRename = false; seed(destination, kind: .directory); seed(try destination.appending("existing.txt"), bytes: Data("keep".utf8)) }
        guard nodes[destination] == nil, nodes[source] != nil else { throw FileOperationError.message("exists or missing") }
        let moving = nodes.filter { $0.key == source || $0.key.remotePath!.rawValue.hasPrefix(source.remotePath!.rawValue + "/") }
        for (old, value) in moving {
            let suffix = String(old.remotePath!.rawValue.dropFirst(source.remotePath!.rawValue.count))
            let new = FileLocation.remote(kind: destination.connectionProtocol!, profileID: destination.profileID!, path: try RemotePath(destination.remotePath!.rawValue + suffix))
            nodes[new] = value; nodes.removeValue(forKey: old)
        }
        if loseRename && nodes[destination]?.kind == .directory { loseRename = false; throw FileOperationError.message("lost reply") }
    }
}
private actor TreeMemoryChannel: RemoteFileChannel {
    let server: TreeMemoryRemote; let location: FileLocation
    init(server: TreeMemoryRemote, location: FileLocation) { self.server = server; self.location = location }
    func read(offset: UInt64, length: UInt32) async throws -> Data { try await server.read(location, offset: offset, length: length) }
    func write(_ data: Data, offset: UInt64) async throws { try await server.write(location, bytes: data, offset: offset) }
    func close() async throws {}
}
