// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import XCTest
import CommanderCore

final class NetworkConnectionTests: XCTestCase, @unchecked Sendable {
    func testRestoredProtocolsCannotTriggerConnectionOrLocalFallback() async throws {
        let manager = RemoteConnectionManager()
        let f = try FixtureDirectory(); _ = try f.file("private.txt")
        for kind in ConnectionProtocol.allCases {
            let id = UUID(); let location = FileLocation.remote(kind: kind, profileID: id, path: try RemotePath(f.url.path))
            do { _ = try await manager.list(location, options: .init()); XCTFail("Restoration must remain disconnected") } catch { }
            let connected = await manager.isConnected(id); XCTAssertFalse(connected)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.url.path).sorted(), [".fixture-owner", "private.txt"])
    }
    func testSFTPProviderRejectsAnotherProtocolsCredentialBeforeNetworking() async throws {
        var profile = ConnectionProfile(host: "127.0.0.1", port: 9, username: "owned")
        profile.protocolKind = .smb; profile.share = "Owned"
        do { try await SFTPConnectionManager().connect(profile, secret: "owned value"); XCTFail("Wrong provider must reject") }
        catch { XCTAssertTrue(error.localizedDescription.contains("requires an SFTP"), error.localizedDescription) }
    }
    func testProtocolHandoffKeepsPaneAndRootThroughCredentialEntry() throws {
        var profile = ConnectionProfile(host: "server.test", port: 445, username: "alice")
        profile.protocolKind = .smb; profile.share = "Team"
        let original = try ConnectionOpenRequest(profile: profile, activePane: .left, destination: .right)
        let retry = try ConnectionOpenRequest(profile: original.credentialEntryProfile, activePane: .left)
        XCTAssertEqual(retry.paneID, .right); XCTAssertEqual(retry.location.connectionProtocol, .smb)
        XCTAssertEqual(retry.location.remotePath?.rawValue, "/")
    }
}
