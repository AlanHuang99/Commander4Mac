import Foundation

public enum FileKind: String, Codable, Sendable { case directory, file, package, symbolicLink }
public enum PlaceholderState: String, Codable, Sendable { case local, notDownloaded, unknown }
public struct FileEntry: Identifiable, Hashable, Sendable {
    public let id: EntryID
    public let location: FileLocation
    public let name: String
    public let kind: FileKind
    public let fileIdentity: FileIdentity?
    public let byteSize: Int64?
    public let modificationDate: Date?
    public let placeholderState: PlaceholderState
    public var isDirectory: Bool { kind == .directory }
    public init(location: FileLocation, name: String, kind: FileKind, fileIdentity: FileIdentity? = nil,
                byteSize: Int64? = nil, modificationDate: Date? = nil, placeholderState: PlaceholderState = .local) {
        self.location = location; self.id = EntryID(location.url); self.name = name; self.kind = kind
        self.fileIdentity = fileIdentity; self.byteSize = byteSize; self.modificationDate = modificationDate
        self.placeholderState = placeholderState
    }
}
public struct DirectorySnapshot: Sendable {
    public let location: FileLocation
    public let entries: [FileEntry]
    public init(location: FileLocation, entries: [FileEntry]) { self.location = location; self.entries = entries }
}
public struct ListingOptions: Sendable {
    public var includeHidden: Bool
    public init(includeHidden: Bool = false) { self.includeHidden = includeHidden }
}
public protocol DirectoryProviding: Sendable {
    func list(_ location: FileLocation, options: ListingOptions) async throws -> DirectorySnapshot
}
