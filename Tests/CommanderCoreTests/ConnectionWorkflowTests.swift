// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import XCTest
import CommanderCore

final class ConnectionWorkflowTests: XCTestCase {
    func testPaneRoutingIsCapturedBeforeAsynchronousConnection() throws {
        var profile = ConnectionProfile(host: "example.test", username: "alice")
        let current = try ConnectionOpenRequest(profile: profile, activePane: .right)
        XCTAssertEqual(current.paneID, .right)
        profile.destination = .left
        let overridden = try ConnectionOpenRequest(profile: profile, activePane: .right)
        XCTAssertEqual(overridden.paneID, .left)
        XCTAssertEqual(current.paneID, .right)
        XCTAssertEqual(current.location.profileID, profile.id)
        XCTAssertEqual(try ConnectionOpenRequest(profile: profile, activePane: .left, destination: .right).paneID, .right)
    }
    func testEndpointEditsCreateNewProviderIdentityInsteadOfRetargetingQueuedLocations() throws {
        let original = ConnectionProfile(host: "one.test", username: "alice")
        var edit = original; edit.host = "two.test"
        let prepared = try ConnectionProfileChange.prepare(edit, previous: original)
        XCTAssertNotEqual(prepared.id, original.id)
        edit = original; edit.username = "bob"
        XCTAssertNotEqual(try ConnectionProfileChange.prepare(edit, previous: original).id, original.id)
        edit = original; edit.name = "Label only"
        XCTAssertEqual(try ConnectionProfileChange.prepare(edit, previous: original).id, original.id)
    }
    func testTransportIdentityGuardCannotRebindAnExistingProfile() throws {
        var guardrail = ConnectionIdentityGuard()
        var profile = ConnectionProfile(host: "one.test", username: "alice")
        try guardrail.bind(profile)
        profile.serverKey = "ssh-ed25519 Zml4dHVyZQ=="; try guardrail.bind(profile)
        var changed = profile; changed.host = "two.test"
        XCTAssertThrowsError(try guardrail.bind(changed))
        changed = profile; changed.serverKey = "ssh-ed25519 Y2hhbmdlZA=="
        XCTAssertThrowsError(try guardrail.bind(changed))
        let newIdentity = try ConnectionProfileChange.prepare(changed, previous: profile)
        XCTAssertNotEqual(newIdentity.id, profile.id)
        XCTAssertNoThrow(try guardrail.bind(newIdentity))
    }
    func testEndpointEditingClearsPriorHostTrust() throws {
        var old = ConnectionProfile(host: "one.test", username: "alice"); old.serverKey = "ssh-ed25519 Zml4dHVyZQ=="
        var changed = old; changed.host = "two.test"
        XCTAssertNil(try ConnectionProfileChange.prepare(changed, previous: old).serverKey)
        changed = old; changed.name = "New label"
        XCTAssertEqual(try ConnectionProfileChange.prepare(changed, previous: old).serverKey, old.serverKey)
    }
    func testKeyMaterialLoadingIsBoundedAndRejectsSymlinks() throws {
        let f = try FixtureDirectory()
        let large = try f.file("large-key", content: String(repeating: "x", count: 1_048_577))
        XCTAssertThrowsError(try LocalKeyMaterial.read(LocationResolver().reference(for: .local(large))))
        let link = f.url.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: large)
        XCTAssertThrowsError(try LocalKeyMaterial.read(LocationResolver().reference(for: .local(link))))
    }
}
