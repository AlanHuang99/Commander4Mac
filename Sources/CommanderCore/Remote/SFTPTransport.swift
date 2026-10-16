import Foundation
import Darwin

public struct RemoteFileMetadata: Sendable, Equatable {
    public let size: UInt64?
    public let permissions: UInt32?
    public let modified: Date?
    public init(size: UInt64?, permissions: UInt32?, modified: Date?) { self.size = size; self.permissions = permissions; self.modified = modified }
    public var kind: FileKind {
        switch (permissions ?? 0) & UInt32(S_IFMT) {
        case UInt32(S_IFDIR): .directory
        case UInt32(S_IFLNK): .symbolicLink
        default: .file
        }
    }
    public var isRegularFile: Bool { (permissions ?? 0) & UInt32(S_IFMT) == UInt32(S_IFREG) }
}
public protocol RemoteFileChannel: Sendable {
    func read(offset: UInt64, length: UInt32) async throws -> Data
    func write(_ data: Data, offset: UInt64) async throws
    func close() async throws
}
public protocol RemoteFileAccess: DirectoryProviding {
    func metadata(_ location: FileLocation) async throws -> RemoteFileMetadata?
    func openFile(_ location: FileLocation, writeExclusive: Bool) async throws -> any RemoteFileChannel
    func rename(_ source: FileLocation, to destination: FileLocation) async throws
    func createDirectory(_ location: FileLocation) async throws
}
