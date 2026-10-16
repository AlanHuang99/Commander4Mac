import Foundation
import Darwin

public protocol LocationResolving: Sendable {
    func reference(for location: FileLocation) throws -> LocationReference
    func resolve(_ reference: LocationReference) -> ResolvedLocation
}
public struct LocationResolver: LocationResolving {
    public init() {}
    public func reference(for location: FileLocation) throws -> LocationReference {
        try location.requireLocal()
        let identity = try Self.identity(at: location.url)
        return LocationReference(bookmark: try location.url.bookmarkData(options: []), displayURL: location.url, expectedIdentity: identity)
    }
    public func resolve(_ reference: LocationReference) -> ResolvedLocation {
        guard FileLocation.local(reference.displayURL).isLocal else { return .needsRelink("This bookmark is not a local file reference.") }
        if (try? Self.identity(at: reference.displayURL)) == reference.expectedIdentity {
            return .available(.local(reference.displayURL))
        }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: reference.bookmark, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale)
            guard FileLocation.local(url).isLocal, try Self.identity(at: url) == reference.expectedIdentity else { return .needsRelink("The saved location now identifies a different item.") }
            return .available(.local(url))
        } catch { return .unavailable("Saved location is unavailable: \(reference.displayURL.path)") }
    }
    public static func identity(at url: URL) throws -> FileIdentity {
        var value = stat()
        guard lstat(url.path, &value) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        return .init(device: Int64(value.st_dev), inode: value.st_ino)
    }
}
