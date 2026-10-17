// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import XCTest
import CommanderCore

final class HostKeyVerificationTests: XCTestCase {
    func testUnknownAndChangedKeysFailClosedAndMatchingKeyPasses() throws {
        let profile = ConnectionProfile(host: "server.test", username: "alice")
        let key = "ssh-ed25519 Zml4dHVyZSBrZXk="
        XCTAssertThrowsError(try HostKeyVerification.verify(profile: profile, observed: key)) { error in
            guard let challenge = error as? HostKeyChallenge else { return XCTFail("Expected identity challenge") }
            XCTAssertTrue(challenge.fingerprint.hasPrefix("SHA256:")); XCTAssertNil(challenge.previousFingerprint)
        }
        var trusted = profile; trusted.serverKey = key
        XCTAssertNoThrow(try HostKeyVerification.verify(profile: trusted, observed: key + " server comment"))
        XCTAssertThrowsError(try HostKeyVerification.verify(profile: trusted, observed: "ssh-ed25519 Y2hhbmdlZA==")) { error in
            XCTAssertNotNil((error as? HostKeyChallenge)?.previousFingerprint)
        }
    }
}
