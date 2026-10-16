import XCTest
import CommanderCore

final class ConnectionProfileTests: XCTestCase {
    func testProfilesValidateAndPersistWithoutSecrets() throws {
        let f = try FixtureDirectory(); let store = ConnectionStore(directory: f.url)
        let profile = try ConnectionProfile(name: "Server", host: "example.test", username: "alice").validated()
        try store.save([profile])
        XCTAssertEqual(store.load().profiles.first?.host, "example.test")
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertFalse(text.contains("\"password\":")); XCTAssertFalse(text.contains("\"secret\":"))
        for host in ["ssh://host", "user@host", "host/path", "bad host", ""] {
            XCTAssertThrowsError(try ConnectionProfile(host: host, username: "alice").validated())
        }
        XCTAssertThrowsError(try ConnectionProfile(host: "host", port: 0, username: "alice").validated())
    }
    func testStoredCredentialsCannotCrossEndpointOrUsernameChanges() throws {
        let store = MemorySecretStore(); let vault = CredentialVault(store: store)
        var profile = ConnectionProfile(host: "first.test", username: "alice")
        try vault.write("test-only password", for: profile)
        XCTAssertEqual(try vault.read(for: profile), "test-only password")
        profile.host = "second.test"
        XCTAssertNil(try vault.read(for: profile))
        profile.host = "first.test"; profile.username = "bob"
        XCTAssertNil(try vault.read(for: profile))
        try vault.remove(for: profile)
        profile.username = "alice"; XCTAssertNil(try vault.read(for: profile))
    }
    func testCredentialScopePreservesUsernameByteIdentity() throws {
        let store = MemorySecretStore(); let vault = CredentialVault(store: store)
        var profile = ConnectionProfile(host: "fixture.test", username: "caf\u{00e9}")
        try vault.write("test-only credential", for: profile)
        let original = profile
        profile.username = "cafe\u{0301}"
        XCTAssertNil(try vault.read(for: profile))
        XCTAssertNotEqual(try ConnectionProfileChange.prepare(profile, previous: original).id, original.id)
    }
    func testCorruptProfilesArePreserved() throws {
        let f = try FixtureDirectory(); let store = ConnectionStore(directory: f.url)
        try Data("bad".utf8).write(to: store.fileURL)
        XCTAssertNotNil(store.load().diagnostic)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.url.path).contains { $0.hasPrefix("connections-corrupt-") })
    }
}
private final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock(); private var values: [String: Data] = [:]
    func read(account: String) throws -> Data? { lock.withLock { values[account] } }
    func write(_ data: Data, account: String) throws { lock.withLock { values[account] = data } }
    func remove(account: String) throws { _ = lock.withLock { values.removeValue(forKey: account) } }
}
