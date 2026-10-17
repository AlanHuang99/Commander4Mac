// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation

public struct ProviderRouter: DirectoryProviding {
    private let local: any DirectoryProviding
    private let remote: any DirectoryProviding
    public init(local: any DirectoryProviding = LocalFileSystem(), remote: any DirectoryProviding) { self.local = local; self.remote = remote }
    public func list(_ location: FileLocation, options: ListingOptions) async throws -> DirectorySnapshot {
        try await (location.isLocal ? local : remote).list(location, options: options)
    }
}
public enum PathNavigation {
    public static func resolve(_ input: String, from current: FileLocation) throws -> FileLocation {
        guard !input.isEmpty else { throw FileOperationError.message("Enter a folder path.") }
        if input.hasPrefix("file://"), let url = URL(string: input), url.isFileURL, url.host == nil || url.host == "localhost" || url.host == "" { return .local(url) }
        guard !input.contains("://") else { throw FileOperationError.message("Use Connect to open a remote server.") }
        if let id = current.profileID, let path = current.remotePath {
            return .remote(kind: current.connectionProtocol!, profileID: id, path: try RemotePath(input.hasPrefix("/") ? input : path.rawValue + "/" + input))
        }
        let expanded = (input as NSString).expandingTildeInPath
        return .local(expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : current.url.appendingPathComponent(expanded))
    }
}
