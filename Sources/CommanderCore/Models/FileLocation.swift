import Foundation

public enum FileLocation: Hashable, Codable, Sendable {
    case local(URL)
    case sftp(profileID: UUID, path: RemotePath)
    case smb(profileID: UUID, path: RemotePath)
    case webdav(profileID: UUID, path: RemotePath)
    public var connectionProtocol: ConnectionProtocol? {
        switch self { case .local: nil; case .sftp: .sftp; case .smb: .smb; case .webdav: .webdav }
    }
    public static func remote(kind: ConnectionProtocol, profileID: UUID, path: RemotePath) -> Self {
        switch kind { case .sftp: .sftp(profileID: profileID, path: path); case .smb: .smb(profileID: profileID, path: path); case .webdav: .webdav(profileID: profileID, path: path) }
    }
    public var isLocal: Bool {
        guard case .local(let url) = self, url.isFileURL else { return false }
        return url.host == nil || url.host == "" || url.host == "localhost"
    }
    public var profileID: UUID? { switch self { case .local: nil; case .sftp(let id, _), .smb(let id, _), .webdav(let id, _): id } }
    public var remotePath: RemotePath? { switch self { case .local: nil; case .sftp(_, let path), .smb(_, let path), .webdav(_, let path): path } }
    public func requireLocal() throws { guard isLocal else { throw FileOperationError.message("This action requires a local location.") } }
    public var url: URL {
        switch self {
        case .local(let url): return url.standardizedFileURL
        case .sftp(let id, let path), .smb(let id, let path), .webdav(let id, let path):
            var c = URLComponents(); c.scheme = "commander-" + connectionProtocol!.rawValue; c.host = id.uuidString.lowercased(); c.path = path.rawValue
            return c.url!
        }
    }
    public var providerID: String { profileID.map { connectionProtocol!.rawValue + ":" + $0.uuidString } ?? "local" }
    public static func == (lhs: FileLocation, rhs: FileLocation) -> Bool {
        guard lhs.providerID == rhs.providerID, lhs.isLocal == rhs.isLocal else { return false }
        if let left = lhs.remotePath, let right = rhs.remotePath { return left == right }
        return lhs.isLocal ? lhs.url.path == rhs.url.path : lhs.url.absoluteString == rhs.url.absoluteString
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(providerID); hasher.combine(isLocal)
        if let remotePath { hasher.combine(remotePath) } else { hasher.combine(isLocal ? url.path : url.absoluteString) }
    }
    public var title: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }
    public var parent: FileLocation {
        switch self { case .local: .local(url.deletingLastPathComponent()); default: .remote(kind: connectionProtocol!, profileID: profileID!, path: remotePath!.parent) }
    }
    public func appending(_ name: String) throws -> FileLocation {
        switch self {
        case .local: return .local(url.appendingPathComponent(try FileNameRules.validateComponent(name)))
        default: return .remote(kind: connectionProtocol!, profileID: profileID!, path: try remotePath!.appending(name))
        }
    }
}
public struct EntryID: RawRepresentable, Hashable, Codable, Sendable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ url: URL) { rawValue = url.isFileURL ? url.standardizedFileURL.path : url.absoluteString }
}
public struct FileIdentity: Hashable, Codable, Sendable {
    public let device: Int64
    public let inode: UInt64
    public init(device: Int64, inode: UInt64) { self.device = device; self.inode = inode }
}
