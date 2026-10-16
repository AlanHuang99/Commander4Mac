import Foundation
import Darwin

public enum TransferKind: String, Codable, Sendable { case copy, move }
public struct TransferRequest: Identifiable, Codable, Sendable {
    public let id: UUID
    public let kind: TransferKind
    public let sources: [FileLocation]
    public let destinationDirectory: FileLocation
    public init(id: UUID = UUID(), kind: TransferKind, sources: [FileLocation], destinationDirectory: FileLocation) {
        self.id = id; self.kind = kind; self.sources = sources; self.destinationDirectory = destinationDirectory
    }
}
public struct ItemVersion: Codable, Equatable, Sendable {
    public let identity: FileIdentity
    public let size: Int64
    public let modifiedSeconds: Int64
    public let modifiedNanoseconds: Int64
    public let mode: UInt16
    public var isDirectory: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFDIR) }
    public static func read(at url: URL) throws -> ItemVersion {
        var value = stat()
        guard lstat(url.path, &value) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        return .init(identity: .init(device: Int64(value.st_dev), inode: value.st_ino), size: value.st_size,
            modifiedSeconds: Int64(value.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(value.st_mtimespec.tv_nsec), mode: value.st_mode)
    }
}
public struct PlannedTransfer: Identifiable, Sendable {
    public let id: UUID
    public let source: FileLocation
    public let destination: URL
    public let sourceVersion: ItemVersion
    public var isDirectory: Bool { sourceVersion.isDirectory }
}
public struct TransferPlan: Sendable {
    public let request: TransferRequest
    public let items: [PlannedTransfer]
    public let destinationIdentity: FileIdentity
}
public enum ConflictDecision: String, Sendable, CaseIterable { case skip, keepBoth, replace, cancel }
public struct ConflictResolution: Sendable {
    public let decision: ConflictDecision
    public let applyToAll: Bool
    public init(_ decision: ConflictDecision, applyToAll: Bool = false) { self.decision = decision; self.applyToAll = applyToAll }
}
public struct TransferConflict: Identifiable, Sendable {
    public let id: UUID
    public let jobID: UUID
    public let source: FileLocation
    public let destination: URL
    public let isDirectory: Bool
}
public enum FileOperationError: LocalizedError, Sendable {
    case message(String)
    public var errorDescription: String? { switch self { case .message(let message): message } }
}
