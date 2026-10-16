import Foundation

/// Recovery identity contains no secret, key reference, or trust material.
public struct RemoteEndpointSnapshot: Codable, Sendable, Equatable {
    public let profileID: UUID; public let name: String; public let protocolKind: ConnectionProtocol
    public let host: String; public let port: Int; public let username: String; public let domain: String
    public let namespace: String; public let secure: Bool
    public init(profile: ConnectionProfile) {
        profileID = profile.id; name = profile.name; protocolKind = profile.protocolKind; host = profile.host; port = profile.port
        username = profile.username; domain = profile.domain; secure = profile.secure
        namespace = profile.protocolKind == .smb ? "/" + profile.share : (profile.protocolKind == .webdav ? profile.basePath : "")
    }
    public func readablePath(_ path: String) -> String {
        var c = URLComponents(); c.scheme = protocolKind == .webdav ? (secure ? "https" : "http") : protocolKind.rawValue
        c.host = host; c.port = port
        let base = namespace == "/" ? "" : namespace
        c.path = base + path
        return c.url?.absoluteString ?? "\(protocolKind.title) \(host):\(port)\(base)\(path)"
    }
    public var label: String { "\(name.isEmpty ? host : name) · \(protocolKind.title) · \(host):\(port)\(namespace)" + (domain.isEmpty ? "" : " · Domain \(domain)") + (username.isEmpty ? "" : " · \(username)") }
}
public enum LocationAction: Sendable, Equatable { case revealLocal(URL), copyRemotePath(String) }
public enum LocationPresentation {
    public static func action(for url: URL, endpoint: RemoteEndpointSnapshot?) -> LocationAction {
        if url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost" { return .revealLocal(url) }
        let kind = ConnectionProtocol.allCases.first { url.scheme == "commander-" + $0.rawValue }
        if let kind, let id = url.host.flatMap(UUID.init(uuidString:)) {
            if let endpoint, endpoint.profileID == id, endpoint.protocolKind == kind { return .copyRemotePath(endpoint.readablePath(url.path)) }
            return .copyRemotePath("\(kind.title) connection \(id.uuidString): \(url.path)")
        }
        return .copyRemotePath(url.absoluteString)
    }
    public static func text(for url: URL, endpoint: RemoteEndpointSnapshot?) -> String {
        switch action(for: url, endpoint: endpoint) { case .revealLocal(let url): url.path; case .copyRemotePath(let path): path }
    }
}
public enum TransferCapabilities {
    public static func canTransfer(_ kind: TransferKind, from source: FileLocation, to destination: FileLocation, entries: [FileEntry]) -> Bool {
        guard !entries.isEmpty else { return false }
        if source.isLocal && destination.isLocal { return true }
        return kind == .copy && source.isLocal != destination.isLocal && entries.allSatisfy { ($0.kind == .file || $0.kind == .directory) && $0.placeholderState != .notDownloaded }
    }
}
