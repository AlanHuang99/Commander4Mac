// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation
import CryptoKit

public struct HostKeyChallenge: Error, LocalizedError, Identifiable, Sendable {
    public var id: UUID { profileID }
    public let profileID: UUID
    public let host: String
    public let port: Int
    public let observedKey: String
    public let fingerprint: String
    public let previousFingerprint: String?
    public var errorDescription: String? { previousFingerprint == nil ? "Verify this server's SSH host key before connecting." : "The server's SSH host key changed. Verify its identity before reconnecting." }
}
public enum HostKeyVerification {
    public static func normalized(_ key: String) -> String { key.split(whereSeparator: \.isWhitespace).prefix(2).joined(separator: " ") }
    public static func fingerprint(_ key: String) -> String {
        let parts = key.split(whereSeparator: \.isWhitespace)
        guard parts.count >= 2, let bytes = Data(base64Encoded: String(parts[1])) else { return "Invalid saved key" }
        return "SHA256:" + Data(SHA256.hash(data: bytes)).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }
    public static func verify(profile: ConnectionProfile, observed: String) throws {
        let key = normalized(observed)
        if let expected = profile.serverKey, normalized(expected) == key { return }
        throw HostKeyChallenge(profileID: profile.id, host: profile.host, port: profile.port, observedKey: key,
                               fingerprint: fingerprint(key), previousFingerprint: profile.serverKey.map(fingerprint))
    }
}
