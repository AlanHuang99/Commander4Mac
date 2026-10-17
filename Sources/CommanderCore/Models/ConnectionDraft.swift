// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation

/// Transient editor state. Credentials are never encoded into the profile catalog.
public struct ConnectionDraft: Sendable {
    public var profile: ConnectionProfile
    public var keyPath: String
    public var secret = ""
    public var remember = true
    public init(profile: ConnectionProfile) {
        self.profile = profile
        keyPath = profile.keyReference?.displayURL.path ?? ""
    }
    public mutating func select(_ profile: ConnectionProfile) { self = Self(profile: profile) }
    public mutating func setProtocol(_ kind: ConnectionProtocol) {
        guard kind != profile.protocolKind else { return }
        profile.protocolKind = kind; profile.port = kind.defaultPort
        profile.authentication = .password; profile.keyReference = nil; profile.serverKey = nil
        profile.initialPath = "/"; profile.share = ""; profile.domain = ""; profile.basePath = "/"; profile.secure = true
        keyPath = ""; secret = ""
    }
    public mutating func setSecure(_ secure: Bool) {
        guard secure != profile.secure else { return }
        profile.secure = secure; secret = ""
        if profile.protocolKind == .webdav && (profile.port == 80 || profile.port == 443) { profile.port = secure ? 443 : 80 }
    }
    public mutating func setAuthentication(_ authentication: SFTPAuthentication) {
        guard authentication != profile.authentication else { return }
        profile.authentication = authentication; secret = ""
        if authentication != .ed25519Key { profile.keyReference = nil; keyPath = "" }
    }
}
