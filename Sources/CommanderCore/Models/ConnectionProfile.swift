import Foundation

public struct RemotePath: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(_ path: String) throws {
        guard path.hasPrefix("/"), !path.contains("\0") else { throw FileOperationError.message("Enter an absolute remote path beginning with /.") }
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            if part == "." { continue }
            if part == ".." {
                guard !parts.isEmpty else { throw FileOperationError.message("The path goes above the server root.") }
                parts.removeLast()
            } else { parts.append(part) }
        }
        rawValue = "/" + parts.joined(separator: "/")
    }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.rawValue.utf8.elementsEqual(rhs.rawValue.utf8) }
    public func hash(into hasher: inout Hasher) { hasher.combine(Data(rawValue.utf8)) }
    public init?(rawValue: String) { guard let valid = try? Self(rawValue) else { return nil }; self = valid }
    public init(from decoder: Decoder) throws { try self.init(decoder.singleValueContainer().decode(String.self)) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
    public var parent: RemotePath { (try? RemotePath(String(rawValue.prefix(upTo: rawValue.lastIndex(of: "/")!)))) ?? (try! RemotePath("/")) }
    public func appending(_ name: String) throws -> RemotePath {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw FileOperationError.message("The server supplied an unsafe filename.")
        }
        return try RemotePath((rawValue == "/" ? "" : rawValue) + "/" + name)
    }
}
public enum ConnectionProtocol: String, Codable, Sendable, CaseIterable {
    case sftp, smb, webdav
    public var title: String { switch self { case .sftp: "SFTP"; case .smb: "SMB"; case .webdav: "WebDAV" } }
    public var defaultPort: Int { switch self { case .sftp: 22; case .smb: 445; case .webdav: 443 } }
}
public enum SFTPAuthentication: String, Codable, Sendable { case password, ed25519Key, guest }
public struct ConnectionProfile: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var username: String
    public var initialPath: String
    public var authentication: SFTPAuthentication
    public var keyReference: LocationReference?
    public var serverKey: String?
    public var destination: OpenDestination?
    public var protocolKind: ConnectionProtocol = .sftp
    public var share = ""
    public var domain = ""
    public var basePath = "/"
    public var secure = true
    public var isLoopback: Bool { ["127.0.0.1", "::1"].contains(host.lowercased()) }
    enum CodingKeys: String, CodingKey { case id, name, host, port, username, initialPath, authentication, keyReference, serverKey, destination, protocolKind, share, domain, basePath, secure }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        host = try c.decode(String.self, forKey: .host); port = try c.decode(Int.self, forKey: .port)
        username = try c.decode(String.self, forKey: .username); initialPath = try c.decode(String.self, forKey: .initialPath)
        authentication = try c.decode(SFTPAuthentication.self, forKey: .authentication)
        keyReference = try c.decodeIfPresent(LocationReference.self, forKey: .keyReference)
        serverKey = try c.decodeIfPresent(String.self, forKey: .serverKey); destination = try c.decodeIfPresent(OpenDestination.self, forKey: .destination)
        protocolKind = try c.decodeIfPresent(ConnectionProtocol.self, forKey: .protocolKind) ?? .sftp
        share = try c.decodeIfPresent(String.self, forKey: .share) ?? ""; domain = try c.decodeIfPresent(String.self, forKey: .domain) ?? ""
        basePath = try c.decodeIfPresent(String.self, forKey: .basePath) ?? "/"; secure = try c.decodeIfPresent(Bool.self, forKey: .secure) ?? true
    }
    public init(id: UUID = UUID(), name: String = "", host: String = "", port: Int = 22, username: String = "",
                initialPath: String = "/", authentication: SFTPAuthentication = .password) {
        self.id = id; self.name = name; self.host = host; self.port = port; self.username = username
        self.initialPath = initialPath; self.authentication = authentication
    }
    public var credentialScope: String {
        let legacy = "\(host.lowercased())\u{0}\(port)\u{0}\(username)\u{0}\(authentication.rawValue)\u{0}\(keyReference.map { String($0.expectedIdentity.device) + ":" + String($0.expectedIdentity.inode) } ?? "")"
        switch protocolKind {
        case .sftp: return legacy
        case .smb: return "smb\u{0}\(domain)\u{0}\(share)\u{0}" + legacy
        case .webdav: return "webdav\u{0}\(secure)\u{0}\(basePath)\u{0}" + legacy
        }
    }
    public func hasSameCredentialScope(as other: ConnectionProfile) -> Bool { credentialScope.utf8.elementsEqual(other.credentialScope.utf8) }
    public func validated() throws -> Self {
        var copy = self; copy.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !copy.host.isEmpty, !copy.host.contains(where: { $0.isWhitespace || $0.isNewline || $0 == "/" || $0 == "@" || $0 == "\0" }),
              !copy.host.contains("://"), (1...65535).contains(port), (authentication == .guest || !username.isEmpty),
              !username.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw FileOperationError.message("Enter a server hostname, port 1–65535, and username. Keep credentials out of the hostname.")
        }
        copy.initialPath = try RemotePath(initialPath).rawValue
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.name.isEmpty { copy.name = copy.host }
        guard !domain.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }), !domain.contains("\\"), !domain.contains("/") else { throw FileOperationError.message("Enter a domain without path separators or control characters.") }
        if protocolKind == .smb { copy.share = try FileNameRules.validateComponent(share) }
        if protocolKind == .webdav {
            copy.basePath = try RemotePath(basePath).rawValue
            guard secure || copy.isLoopback else { throw FileOperationError.message("WebDAV requires HTTPS. HTTP is allowed only for numeric loopback servers.") }
        }
        guard (authentication != .ed25519Key || protocolKind == .sftp), (authentication != .guest || protocolKind != .sftp) else { throw FileOperationError.message("Choose an authentication method supported by this protocol.") }
        if authentication == .ed25519Key && keyReference == nil { throw FileOperationError.message("Choose an OpenSSH Ed25519 private key.") }
        return copy
    }
}
