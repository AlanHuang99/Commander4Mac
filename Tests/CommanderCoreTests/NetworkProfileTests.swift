// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import XCTest
import CommanderCore

final class NetworkProfileTests: XCTestCase {
    func testLegacySFTPScopeAndJSONRemainCompatible() throws {
        let profile = ConnectionProfile(host: "old.test", username: "alice")
        let original = profile.credentialScope
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as! [String: Any]
        json.removeValue(forKey: "protocolKind"); json.removeValue(forKey: "share"); json.removeValue(forKey: "domain"); json.removeValue(forKey: "basePath")
        let restored = try JSONDecoder().decode(ConnectionProfile.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.protocolKind, .sftp); XCTAssertEqual(restored.credentialScope, original)
        XCTAssertEqual(original, "old.test\u{0}22\u{0}alice\u{0}password\u{0}")
    }
    func testProtocolAndRootChangesCannotReuseIdentityOrCredentials() throws {
        var smb = ConnectionProfile(host: "server.test", port: 445, username: "alice")
        smb.protocolKind = .smb; smb.share = "Team Share"; smb.domain = "TEAM"
        let valid = try smb.validated(); XCTAssertEqual(valid.share, "Team Share")
        var changed = smb; changed.share = "Other"
        XCTAssertNotEqual(try ConnectionProfileChange.prepare(changed, previous: smb).id, smb.id)
        changed = smb; changed.domain = "OTHER"
        XCTAssertNotEqual(try ConnectionProfileChange.prepare(changed, previous: smb).id, smb.id)
        var dav = smb; dav.protocolKind = .webdav; dav.port = 443; dav.basePath = "/dav/team"; dav.share = ""; dav.domain = ""
        XCTAssertNotEqual(dav.credentialScope, smb.credentialScope)
        changed = dav; changed.basePath = "/dav/other"
        XCTAssertNotEqual(try ConnectionProfileChange.prepare(changed, previous: dav).id, dav.id)
        smb.share = "../bad"; XCTAssertThrowsError(try smb.validated())
        dav.authentication = .ed25519Key; XCTAssertThrowsError(try dav.validated())
    }
    func testRemoteProtocolSurvivesPathsAndSessionRestoration() throws {
        let id = UUID()
        for kind in [ConnectionProtocol.smb, .webdav] {
            let location = FileLocation.remote(kind: kind, profileID: id, path: try RemotePath("/team"))
            XCTAssertFalse(location.isLocal); XCTAssertEqual(location.connectionProtocol, kind)
            let child = try PathNavigation.resolve("子 #%.txt", from: location)
            XCTAssertEqual(child.connectionProtocol, kind); XCTAssertEqual(child.parent, location)
            XCTAssertNotEqual(child, .sftp(profileID: id, path: child.remotePath!))
            let roundTrip = try JSONDecoder().decode(FileLocation.self, from: JSONEncoder().encode(child))
            XCTAssertEqual(roundTrip, child); XCTAssertThrowsError(try roundTrip.requireLocal())
        }
    }
}
