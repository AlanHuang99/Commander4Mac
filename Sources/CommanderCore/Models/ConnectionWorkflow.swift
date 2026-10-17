// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation

public struct ConnectionOpenRequest: Sendable {
    public let profile: ConnectionProfile
    public let paneID: PaneID
    public let location: FileLocation
    /// Credential entry retains the resolved destination, even when focus or
    /// application defaults change while Keychain is being consulted.
    public var credentialEntryProfile: ConnectionProfile {
        var result = profile; result.destination = paneID == .left ? .left : .right; return result
    }
    public init(profile: ConnectionProfile, activePane: PaneID, destination: OpenDestination? = nil, defaultDestination: OpenDestination = .current) throws {
        self.profile = try profile.validated()
        let route = destination ?? profile.destination ?? defaultDestination
        paneID = route == .current ? activePane : (route == .left ? .left : .right)
        location = .remote(kind: profile.protocolKind, profileID: profile.id, path: try RemotePath(profile.initialPath))
    }
}
public enum ConnectionProfileChange {
    public static func prepare(_ candidate: ConnectionProfile, previous: ConnectionProfile?) throws -> ConnectionProfile {
        var result = try candidate.validated()
        if let previous {
            if previous.protocolKind != result.protocolKind || previous.host.lowercased() != result.host.lowercased() || previous.port != result.port { result.serverKey = nil }
            let replacedTrust = previous.serverKey.map { HostKeyVerification.normalized($0) } != nil &&
                previous.serverKey.map { HostKeyVerification.normalized($0) } != result.serverKey.map { HostKeyVerification.normalized($0) }
            if !previous.hasSameCredentialScope(as: result) || replacedTrust { result.id = UUID() }
        }
        return result
    }
}
public enum SFTPConnectionState: String, Sendable {
    case disconnected = "Disconnected", connecting = "Connecting", verificationRequired = "Verify server identity", connected = "Connected", failed = "Connection failed"
}

/// A profile ID cannot change endpoint, login namespace, or established host identity
/// while requests referring to that ID may still exist.
public struct ConnectionIdentityGuard: Sendable {
    private struct Binding: Sendable { let scope: Data; let key: String? }
    private var bindings: [UUID: Binding] = [:]
    public init() {}
    public mutating func bind(_ profile: ConnectionProfile) throws {
        let binding = Binding(scope: Data(profile.credentialScope.utf8), key: profile.serverKey.map(HostKeyVerification.normalized))
        if let old = bindings[profile.id], old.scope != binding.scope || (old.key != nil && old.key != binding.key) {
            throw FileOperationError.message("Save this server or login change as a new connection identity before connecting. Existing requests were not redirected.")
        }
        bindings[profile.id] = binding
    }
}
