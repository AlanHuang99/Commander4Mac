import XCTest
import CommanderCore

final class ConnectionFixTests: XCTestCase, @unchecked Sendable {
    @MainActor func testCancelDuringPreparationCannotConnectOrCompleteAfterDismissal() async {
        let barrier = ConnectionTestBarrier()
        let workflow = ConnectionSubmission()
        var connected = false; var finished = false
        let job = workflow.start(prepare: { await barrier.wait(); return 7 }, perform: { _ in connected = true }, completion: { _ in finished = true })
        while !barrier.isWaiting { await Task.yield() }
        workflow.cancel()
        barrier.release()
        await job.value
        XCTAssertFalse(connected); XCTAssertFalse(finished)
    }
    @MainActor func testCancelDuringConnectCancelsOwnedTaskWithoutCompletingDismissedSheet() async {
        let barrier = ConnectionTestBarrier()
        let workflow = ConnectionSubmission()
        var observedCancellation = false; var finished = false
        let job = workflow.start(prepare: { 7 }, perform: { _ in
            await barrier.wait(); observedCancellation = Task.isCancelled
        }, completion: { _ in finished = true })
        while !barrier.isWaiting { await Task.yield() }
        workflow.cancel(); barrier.release(); await job.value
        XCTAssertTrue(observedCancellation); XCTAssertFalse(finished)
    }
    func testMissingCredentialHandoffPreservesExplicitPaneAfterFocusChanges() throws {
        var profile = ConnectionProfile(host: "fixture.test", username: "alice"); profile.destination = .current
        let captured = try ConnectionOpenRequest(profile: profile, activePane: .left, destination: .right)
        let handoff = captured.credentialEntryProfile
        let submitted = try ConnectionOpenRequest(profile: handoff, activePane: .left, defaultDestination: .left)
        XCTAssertEqual(submitted.paneID, .right)
        XCTAssertEqual(submitted.location, captured.location)
    }
    func testFailedRotatingProfileSaveRetainsOldCredentialAndRollsBackPreparedItem() throws {
        let secrets = CommitTestSecrets(); let vault = CredentialVault(store: secrets)
        let old = ConnectionProfile(host: "old.test", username: "alice")
        try vault.write("owned old secret", for: old)
        var edit = old; edit.host = "new.test"
        let prepared = try ConnectionProfileChange.prepare(edit, previous: old)
        let commit = ConnectionProfileCommit(store: FailingProfileDocument(), vault: vault)
        XCTAssertThrowsError(try commit.save(profiles: [prepared], previous: old, prepared: prepared, secret: "owned new secret", remember: true, allowCredentialTransfer: false))
        XCTAssertEqual(try vault.read(for: old), "owned old secret")
        XCTAssertNil(try vault.read(for: prepared))
    }
    func testFailedSameIdentitySaveRollsBackPasswordAndFailedRemoveRetainsIt() throws {
        let secrets = CommitTestSecrets(); let vault = CredentialVault(store: secrets)
        let old = ConnectionProfile(host: "old.test", username: "alice")
        try vault.write("owned old secret", for: old)
        let commit = ConnectionProfileCommit(store: FailingProfileDocument(), vault: vault)
        XCTAssertThrowsError(try commit.save(profiles: [old], previous: old, prepared: old, secret: "owned new secret", remember: true, allowCredentialTransfer: false))
        XCTAssertEqual(try vault.read(for: old), "owned old secret")
        XCTAssertThrowsError(try commit.remove(profiles: [], removed: old))
        XCTAssertEqual(try vault.read(for: old), "owned old secret")
    }
}
@MainActor private final class ConnectionTestBarrier {
    private(set) var isWaiting = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { continuation = $0; isWaiting = true } }
    func release() { continuation?.resume(); continuation = nil }
}
private struct FailingProfileDocument: ConnectionProfilePersisting {
    func save(_ profiles: [ConnectionProfile]) throws { throw FileOperationError.message("Injected profile persistence failure") }
}
private final class CommitTestSecrets: SecretStore, @unchecked Sendable {
    private let lock = NSLock(); private var values: [String: Data] = [:]
    func read(account: String) throws -> Data? { lock.withLock { values[account] } }
    func write(_ data: Data, account: String) throws { lock.withLock { values[account] = data } }
    func remove(account: String) throws { _ = lock.withLock { values.removeValue(forKey: account) } }
}
