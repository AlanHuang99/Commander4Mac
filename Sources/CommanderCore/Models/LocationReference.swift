import Foundation

public struct LocationReference: Codable, Hashable, Sendable {
    public var bookmark: Data
    public let displayURL: URL
    public let expectedIdentity: FileIdentity
    public init(bookmark: Data, displayURL: URL, expectedIdentity: FileIdentity) {
        self.bookmark = bookmark; self.displayURL = displayURL; self.expectedIdentity = expectedIdentity
    }
}
public enum ResolvedLocation: Sendable { case available(FileLocation), unavailable(String), needsRelink(String) }
public struct Favorite: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var reference: LocationReference
    public var destination: OpenDestination?
}
public struct StagedItem: Identifiable, Codable, Sendable {
    public let id: UUID
    public var reference: LocationReference
    public let displayName: String
    public init(id: UUID = UUID(), reference: LocationReference, displayName: String) {
        self.id = id; self.reference = reference; self.displayName = displayName
    }
}
