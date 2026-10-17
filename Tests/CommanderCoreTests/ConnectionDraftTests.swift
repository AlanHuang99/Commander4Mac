// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import XCTest
@testable import CommanderCore

final class ConnectionDraftTests: XCTestCase {
    func testSelectingSavedProfilePreservesEndpointAndClearsTransientCredential() throws {
        var smb = ConnectionProfile(name: "Studio", host: "files.example.test", port: 1445, username: "artist", initialPath: "/Projects")
        smb.protocolKind = .smb; smb.share = "Design"; smb.domain = "STUDIO"
        var draft = ConnectionDraft(profile: ConnectionProfile())
        draft.secret = "temporary"; draft.remember = false; draft.keyPath = "/old/key"
        draft.select(smb)
        XCTAssertEqual(draft.profile, smb)
        XCTAssertEqual(draft.secret, ""); XCTAssertEqual(draft.keyPath, ""); XCTAssertTrue(draft.remember)
        var dav = ConnectionProfile(name: "Studio", host: "dav.example.test", port: 8443, username: "artist", initialPath: "/Drafts")
        dav.protocolKind = .webdav; dav.basePath = "/collections/work"
        draft.secret = "another temporary credential"; draft.select(dav)
        XCTAssertEqual(draft.profile, dav)
        XCTAssertNotEqual(draft.profile.id, smb.id); XCTAssertEqual(draft.secret, "")
    }

    func testOnlyUserProtocolChangeResetsProtocolDefaults() {
        var saved = ConnectionProfile(host: "files.example.test", port: 1445, username: "artist", initialPath: "/Projects")
        saved.protocolKind = .smb; saved.share = "Design"; saved.domain = "STUDIO"
        var draft = ConnectionDraft(profile: saved)
        draft.setProtocol(.smb)
        XCTAssertEqual(draft.profile, saved)
        draft.secret = "temporary"; draft.setProtocol(.webdav)
        XCTAssertEqual(draft.profile.port, 443); XCTAssertEqual(draft.profile.initialPath, "/")
        XCTAssertEqual(draft.profile.share, ""); XCTAssertEqual(draft.profile.domain, "")
        XCTAssertEqual(draft.profile.authentication, .password); XCTAssertEqual(draft.secret, "")
        XCTAssertEqual(draft.profile.host, saved.host); XCTAssertEqual(draft.profile.id, saved.id)
    }

    func testUserHTTPSChangePreservesCustomPortAndClearsCredential() {
        var profile = ConnectionProfile(port: 8443); profile.protocolKind = .webdav
        var draft = ConnectionDraft(profile: profile); draft.secret = "temporary"
        draft.setSecure(false)
        XCTAssertEqual(draft.profile.port, 8443); XCTAssertEqual(draft.secret, "")
        draft.profile.port = 80; draft.setSecure(true)
        XCTAssertEqual(draft.profile.port, 443)
        draft.setSecure(false); XCTAssertEqual(draft.profile.port, 80)
    }

    func testAuthenticationSwitchCannotReuseTransientPasswordAsKeyPassphrase() {
        var draft = ConnectionDraft(profile: ConnectionProfile())
        draft.secret = "password"; draft.setAuthentication(.ed25519Key)
        XCTAssertEqual(draft.secret, "")
        draft.keyPath = "/some/key"; draft.secret = "passphrase"; draft.setAuthentication(.password)
        XCTAssertEqual(draft.secret, ""); XCTAssertEqual(draft.keyPath, "")
        XCTAssertNil(draft.profile.keyReference)
    }
}
