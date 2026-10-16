import XCTest
import CommanderCore

final class SMBIntegrationTests: XCTestCase, @unchecked Sendable {
    func testOwnedSMBBrowsingAndNonReplacingOperations() async throws {
        guard let fixture = ProcessInfo.processInfo.environment["COMMANDER_SMB_FIXTURE"] else { throw XCTSkip("Owned loopback SMB fixture required") }
        let root = URL(fileURLWithPath: fixture)
        let config = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("fixture.json"))) as! [String: Any]
        var profile = ConnectionProfile(host: "127.0.0.1", port: config["port"] as! Int, username: config["username"] as! String)
        profile.protocolKind = .smb; profile.share = "OwnedShare"
        let manager = SMBConnectionManager()
        try await manager.connect(profile, secret: config["secret"] as! String)
        let location = FileLocation.smb(profileID: profile.id, path: try RemotePath("/"))
        do {
            let listing = try await manager.list(location, options: .init())
            XCTAssertTrue(listing.entries.contains { $0.name == "hello #中文.txt" })
            let rootMetadata = try await manager.metadata(location); XCTAssertEqual(rootMetadata?.kind, .directory)
            let original = try location.appending("hello #中文.txt")
            let originalMetadata = try await manager.metadata(original); XCTAssertTrue(originalMetadata?.isRegularFile == true)
            let missingMetadata = try await manager.metadata(location.appending("missing.bin")); XCTAssertNil(missingMetadata)
            let reader = try await manager.openFile(original, writeExclusive: false)
            let data = try await reader.read(offset: 0, length: 65536); try await reader.close()
            XCTAssertEqual(data, Data("owned SMB fixture".utf8))
            do { _ = try await manager.openFile(original, writeExclusive: true); XCTFail("Exclusive create must refuse existing files") } catch { }
            let upload = try location.appending("uploaded.txt")
            let writer = try await manager.openFile(upload, writeExclusive: true)
            try await writer.write(Data("owned upload".utf8), offset: 0); try await writer.close()
            do { try await manager.rename(upload, to: original); XCTFail("Rename must not replace") } catch { }
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("data/hello #中文.txt")), Data("owned SMB fixture".utf8))
            try await manager.rename(upload, to: location.appending("renamed.txt"))
            try await manager.createDirectory(location.appending("created folder"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("data/created folder").path))
            let local = try FixtureDirectory(); let source = try local.file("round trip #中文.bin", content: String(repeating: "owned bytes", count: 20_000))
            let downloads = try local.directory("downloads")
            let executor = RemoteTransferExecutor(remote: manager, journal: .init(directory: local.url.appendingPathComponent("journal")))
            let up = await executor.executeRequest(.init(kind: .copy, sources: [.local(source)], destinationDirectory: location), cancellation: .init(), resolveConflict: { _ in .init(.skip) }, emit: { _ in })
            XCTAssertEqual(up.state, .completed, up.outcomes.first?.detail ?? "")
            let down = await executor.executeRequest(.init(kind: .copy, sources: [try location.appending(source.lastPathComponent)], destinationDirectory: .local(downloads)), cancellation: .init(), resolveConflict: { _ in .init(.skip) }, emit: { _ in })
            XCTAssertEqual(down.state, .completed, down.outcomes.first?.detail ?? "")
            XCTAssertEqual(try Data(contentsOf: source), try Data(contentsOf: downloads.appendingPathComponent(source.lastPathComponent)))
            try await assertNetworkTreeRoundTrip(remote: manager, root: location)
        } catch { await manager.disconnect(profile.id); throw error }
        await manager.disconnect(profile.id)
        let connected = await manager.isConnected(profile.id); XCTAssertFalse(connected)
        do { _ = try await manager.list(location, options: .init()); XCTFail("Disconnected mounts cannot fall through to local directories") } catch { }
    }
    @MainActor func testCanceledConnectionCannotBeginAQueuedHandshake() async throws {
        let manager = SMBConnectionManager()
        var profile = ConnectionProfile(host: "127.0.0.1", port: 9, username: "owned"); profile.protocolKind = .smb; profile.share = "OwnedShare"
        let captured = profile
        var release: CheckedContinuation<Void, Never>?
        let job = Task { await withCheckedContinuation { release = $0 }; try await manager.connect(captured, secret: "owned disposable value") }
        while release == nil { await Task.yield() }
        job.cancel(); release?.resume()
        do { try await job.value; XCTFail("Canceled workflow must stop") } catch { XCTAssertTrue(error is CancellationError) }
        let connected = await manager.isConnected(profile.id); XCTAssertFalse(connected)
    }
    func testSMBProviderCannotReadAnOrdinaryLocalDirectory() async throws {
        let f = try FixtureDirectory(); _ = try f.file("keep.txt")
        let manager = SMBConnectionManager()
        do { _ = try await manager.list(.local(f.url), options: .init()); XCTFail("SMB must not fall through to local filesystem") } catch { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.url.appendingPathComponent("keep.txt").path))
    }
}
