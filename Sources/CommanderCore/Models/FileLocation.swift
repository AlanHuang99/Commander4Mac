import Foundation

public enum FileLocation: Hashable, Codable, Sendable {
    case local(URL)
    public var url: URL { switch self { case .local(let url): url.standardizedFileURL } }
    public var providerID: String { "local" }
    public var title: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }
    public var parent: FileLocation { .local(url.deletingLastPathComponent()) }
}
public struct EntryID: RawRepresentable, Hashable, Codable, Sendable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ url: URL) { rawValue = url.standardizedFileURL.path }
}
public struct FileIdentity: Hashable, Codable, Sendable {
    public let device: Int64
    public let inode: UInt64
    public init(device: Int64, inode: UInt64) { self.device = device; self.inode = inode }
}
