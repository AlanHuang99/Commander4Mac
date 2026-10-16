import Foundation
import Darwin

public protocol FileOperationBackend: Sendable {
    func version(at url: URL) throws -> ItemVersion
    func supportsAtomicMove(from source: URL, to destination: URL) -> Bool
    func renameExclusive(from source: URL, to destination: URL) throws
    func swap(_ first: URL, _ second: URL) throws
    func removeSource(at url: URL, expecting version: ItemVersion) throws
}
public struct SystemFileOperationBackend: FileOperationBackend {
    public init() {}
    public func version(at url: URL) throws -> ItemVersion { try ItemVersion.read(at: url) }
    public func supportsAtomicMove(from source: URL, to destination: URL) -> Bool {
        guard let source = try? ItemVersion.read(at: source),
              let target = try? ItemVersion.read(at: destination.deletingLastPathComponent().resolvingSymlinksInPath()) else { return false }
        return source.identity.device == target.identity.device
    }
    public func renameExclusive(from source: URL, to destination: URL) throws {
        if renameatx_np(AT_FDCWD, source.path, AT_FDCWD, destination.path, UInt32(RENAME_EXCL)) != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
    public func swap(_ first: URL, _ second: URL) throws {
        if renameatx_np(AT_FDCWD, first.path, AT_FDCWD, second.path, UInt32(RENAME_SWAP)) != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
    public func removeSource(at url: URL, expecting version: ItemVersion) throws {
        guard try self.version(at: url) == version else { throw FileOperationError.message("The source changed before removal. Both copies have been retained.") }
        try FileManager.default.removeItem(at: url)
    }
}
