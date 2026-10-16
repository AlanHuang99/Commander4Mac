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
public enum SFTPAuthentication: String, Codable, Sendable { case password, ed25519Key }
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
    public init(id: UUID = UUID(), name: String = "", host: String = "", port: Int = 22, username: String = "",
                initialPath: String = "/", authentication: SFTPAuthentication = .password) {
        self.id = id; self.name = name; self.host = host; self.port = port; self.username = username
        self.initialPath = initialPath; self.authentication = authentication
    }
    public var credentialScope: String { "\(host.lowercased())\u{0}\(port)\u{0}\(username)\u{0}\(authentication.rawValue)" }
    public func validated() throws -> Self {
        var copy = self; copy.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !copy.host.isEmpty, !copy.host.contains(where: { $0.isWhitespace || $0.isNewline || $0 == "/" || $0 == "@" || $0 == "\0" }),
              !copy.host.contains("://"), (1...65535).contains(port), !username.isEmpty,
              !username.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw FileOperationError.message("Enter a server hostname, port 1–65535, and username. Keep credentials out of the hostname.")
        }
        copy.initialPath = try RemotePath(initialPath).rawValue
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.name.isEmpty { copy.name = copy.host }
        if authentication == .ed25519Key && keyReference == nil { throw FileOperationError.message("Choose an OpenSSH Ed25519 private key.") }
        return copy
    }
}
