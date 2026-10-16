import XCTest
import CommanderCore

final class NetworkRecoveryTests: XCTestCase, @unchecked Sendable {
    func testFolderCopyCapabilitiesShareOnePredicate() throws {
        let local = FileLocation.local(URL(fileURLWithPath: "/owned")); let remote = FileLocation.smb(profileID: UUID(), path: try RemotePath("/"))
        for kind in [FileKind.file, .directory] {
            let entry = FileEntry(location: try local.appending("item"), name: "item", kind: kind)
            XCTAssertTrue(TransferCapabilities.canTransfer(.copy, from: local, to: remote, entries: [entry]))
            XCTAssertFalse(TransferCapabilities.canTransfer(.move, from: local, to: remote, entries: [entry]))
            XCTAssertFalse(TransferCapabilities.canTransfer(.copy, from: remote, to: remote, entries: [entry]))
        }
        for kind in [FileKind.symbolicLink, .package] {
            let entry = FileEntry(location: try local.appending("item"), name: "item", kind: kind)
            XCTAssertFalse(TransferCapabilities.canTransfer(.copy, from: local, to: remote, entries: [entry]))
            XCTAssertTrue(TransferCapabilities.canTransfer(.copy, from: local, to: local, entries: [entry]))
        }
    }
    func testInterruptedTreeKeepsEndpointIdentityAfterProfileRetires() async throws {
        let f = try FixtureDirectory(); let source = try f.directory("tree"); _ = try f.file("tree/file", content: "owned")
        let remote = TreeMemoryRemote(); var profile = ConnectionProfile(id: remote.root.profileID!, name: "Retired server", host: "files.example.test", username: "alice")
        profile.serverKey = "not recovery metadata"; await remote.setEndpoint(RemoteEndpointSnapshot(profile: profile)); await remote.configure(loseRename: true)
        let journal = OperationJournal(directory: f.url.appendingPathComponent("journal"))
        let result = await RemoteTransferExecutor(remote: remote, journal: journal).executeRequest(.init(kind: .copy, sources: [.local(source)], destinationDirectory: remote.root), cancellation: .init(), resolveConflict: { _ in .init(.skip) }, emit: { _ in })
        XCTAssertEqual(result.outcomes.first?.state, .partial)
        let record = try XCTUnwrap(journal.recoverableJobs().first)
        XCTAssertEqual(record.endpointSnapshot?.host, "files.example.test")
        XCTAssertEqual(record.endpointSnapshot?.profileID, profile.id)
        let json = String(decoding: try JSONEncoder().encode(record), as: UTF8.self)
        XCTAssertFalse(json.contains("serverKey")); XCTAssertFalse(json.contains("keyReference")); XCTAssertFalse(json.contains("not recovery metadata"))
        let action = LocationPresentation.action(for: record.destination, endpoint: record.endpointSnapshot)
        guard case .copyRemotePath(let path) = action else { return XCTFail("Never reveal internal remote URLs in Finder") }
        XCTAssertTrue(path.contains("files.example.test")); XCTAssertTrue(path.contains("tree"))
    }
    func testLegacyJournalAndLocalRevealStillWork() throws {
        let local = FileLocation.local(URL(fileURLWithPath: "/owned"))
        let record = JournalRecord(jobID: UUID(), itemID: UUID(), source: local, destination: local.url, staging: nil, phase: .copying)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as! [String: Any]; object.removeValue(forKey: "endpointSnapshot")
        let decoded = try JSONDecoder().decode(JournalRecord.self, from: JSONSerialization.data(withJSONObject: object)); XCTAssertNil(decoded.endpointSnapshot)
        XCTAssertEqual(LocationPresentation.action(for: local.url, endpoint: nil), .revealLocal(local.url))
        let remote = FileLocation.webdav(profileID: UUID(), path: try RemotePath("/literal #%.txt"))
        guard case .copyRemotePath(let fallback) = LocationPresentation.action(for: remote.url, endpoint: nil) else { return XCTFail("Remote fallback is never Finder") }
        XCTAssertTrue(fallback.contains("/literal #%.txt"))
    }
}
