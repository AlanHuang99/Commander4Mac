import XCTest
import CommanderCore

final class WebDAVIntegrationTests: XCTestCase, @unchecked Sendable {
    private func fixture() throws -> (URL, ConnectionProfile, String) {
        guard let path = ProcessInfo.processInfo.environment["COMMANDER_DAV_FIXTURE"] else { throw XCTSkip("Owned loopback WebDAV fixture required") }
        let root = URL(fileURLWithPath: path)
        let c = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("fixture.json"))) as! [String: Any]
        var p = ConnectionProfile(host: "127.0.0.1", port: c["port"] as! Int, username: c["username"] as! String); p.protocolKind = .webdav; p.secure = false; p.basePath = "/dav"
        return (root, p, c["secret"] as! String)
    }
    func testUnifiedRouterConnectsAndKeepsProtocolIdentity() async throws {
        let (_, p, secret) = try fixture(); let manager = RemoteConnectionManager()
        try await manager.connect(p, secret: secret)
        let root = FileLocation.webdav(profileID: p.id, path: try RemotePath("/"))
        let listing = try await manager.list(root, options: .init()); XCTAssertFalse(listing.entries.isEmpty)
        do { _ = try await manager.list(.smb(profileID: p.id, path: try RemotePath("/")), options: .init()); XCTFail("A profile cannot cross protocols") } catch { }
        await manager.disconnectAll(); let connected = await manager.isConnected(p.id); XCTAssertFalse(connected)
    }
    func testAuthenticatedRealBytesAndExclusiveMutations() async throws {
        let (fixture, p, secret) = try fixture(); let manager = WebDAVConnectionManager()
        try await manager.connect(p, secret: secret)
        let root = FileLocation.webdav(profileID: p.id, path: try RemotePath("/"))
        do {
            let listing = try await manager.list(root, options: .init()); XCTAssertTrue(listing.entries.contains { $0.name == "hello #中文.txt" })
            let original = try root.appending("hello #中文.txt")
            let reader = try await manager.openFile(original, writeExclusive: false)
            let bytes = try await reader.read(offset: 0, length: 65536); try await reader.close()
            XCTAssertEqual(bytes, Data("owned WebDAV fixture".utf8))
            let overwrite = try await manager.openFile(original, writeExclusive: true)
            try await overwrite.write(Data("must not replace".utf8), offset: 0)
            do { try await overwrite.close(); XCTFail("PUT must honor If-None-Match") } catch { }
            let upload = try root.appending("upload #%.txt"); let writer = try await manager.openFile(upload, writeExclusive: true)
            try await writer.write(Data("owned upload".utf8), offset: 0); try await writer.close()
            do { try await manager.rename(upload, to: original); XCTFail("MOVE must honor Overwrite:F") } catch { }
            try await manager.rename(upload, to: root.appending("renamed.txt"))
            try await manager.createDirectory(root.appending("created"))
            let aborted = try root.appending("aborted.txt"); let abort = try await manager.openFile(aborted, writeExclusive: true)
            try await abort.write(Data("never uploaded".utf8), offset: 0); await abort.abort(); try await abort.close()
            let absent = try await manager.metadata(aborted); XCTAssertNil(absent)
            let missing = try await manager.metadata(root.appending("missing")); XCTAssertNil(missing)
            XCTAssertEqual(try Data(contentsOf: fixture.appendingPathComponent("data/hello #中文.txt")), bytes)
            let f = try FixtureDirectory(); let source = try f.file("round trip #%.bin", content: String(repeating: "owned", count: 45000)); let downloads = try f.directory("downloads")
            let engine = RemoteTransferExecutor(remote: manager, journal: .init(directory: f.url.appendingPathComponent("journal")))
            let up = await engine.executeRequest(.init(kind: .copy, sources: [.local(source)], destinationDirectory: root), cancellation: .init(), resolveConflict: { _ in .init(.skip) }, emit: { _ in })
            XCTAssertEqual(up.state, .completed, up.outcomes.first?.detail ?? "")
            let down = await engine.executeRequest(.init(kind: .copy, sources: [try root.appending(source.lastPathComponent)], destinationDirectory: .local(downloads)), cancellation: .init(), resolveConflict: { _ in .init(.skip) }, emit: { _ in })
            XCTAssertEqual(down.state, .completed, down.outcomes.first?.detail ?? "")
            XCTAssertEqual(try Data(contentsOf: source), try Data(contentsOf: downloads.appendingPathComponent(source.lastPathComponent)))
        } catch { await manager.disconnect(p.id); throw error }
        await manager.disconnect(p.id)
    }
    func testDeniedRedirectOversizeAndPartialMutationAreFailures() async throws {
        let (_, p, secret) = try fixture(); let manager = WebDAVConnectionManager(); try await manager.connect(p, secret: secret)
        let root = FileLocation.webdav(profileID: p.id, path: try RemotePath("/"))
        for name in ["denied", "redirect", "oversize"] {
            do { _ = try await manager.list(root.appending(name), options: .init()); XCTFail("Must reject \(name)") }
            catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        }
        do { try await manager.createDirectory(root.appending("partial")); XCTFail("207 is not a successful mutation") } catch { }
        await manager.disconnect(p.id)
        var bad = p; bad.id = UUID()
        do { try await manager.connect(bad, secret: "invalid disposable password"); XCTFail("Authentication failure must not connect") } catch { }
        let connected = await manager.isConnected(bad.id); XCTAssertFalse(connected)
    }
    func testStalledGETCancellationAndDisconnectRetireOwnedRequests() async throws {
        let (_, p, secret) = try fixture(); let manager = WebDAVConnectionManager(); try await manager.connect(p, secret: secret)
        let file = FileLocation.webdav(profileID: p.id, path: try RemotePath("/stall.bin"))
        let task = Task { try await manager.openFile(file, writeExclusive: false) }
        try await Task.sleep(for: .milliseconds(400)); let start = ContinuousClock.now; task.cancel()
        do { _ = try await task.value; XCTFail("Canceled GET cannot complete") } catch { }
        XCTAssertLessThan(start.duration(to: .now), .seconds(3))
        await manager.disconnect(p.id)
        do { _ = try await manager.list(.local(URL(fileURLWithPath: "/")), options: .init()); XCTFail("No local fallback") } catch { }
    }
}
