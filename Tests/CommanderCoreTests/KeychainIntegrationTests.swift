import XCTest
import CommanderCore

final class KeychainIntegrationTests: XCTestCase {
    func testOwnedKeychainCredentialRoundTripAndRemoval() throws {
        guard ProcessInfo.processInfo.environment["COMMANDER_TEST_KEYCHAIN"] == "1" else { throw XCTSkip("Opt-in owned Keychain integration") }
        let store = KeychainSecretStore(service: "Commander4Mac.Tests." + UUID().uuidString)
        let profile = ConnectionProfile(host: "fixture.invalid", username: "fixture")
        let vault = CredentialVault(store: store)
        defer { try? vault.remove(for: profile) }
        try vault.write("owned test credential", for: profile)
        XCTAssertEqual(try vault.read(for: profile), "owned test credential")
        try vault.remove(for: profile)
        XCTAssertNil(try vault.read(for: profile))
    }
}
