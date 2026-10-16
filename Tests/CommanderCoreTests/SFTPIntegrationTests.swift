import XCTest
import CommanderCore
import Darwin

final class SFTPIntegrationTests: XCTestCase, @unchecked Sendable {
    func testRealSFTPKeyVerificationListingAndFileOperations() async throws {
        guard let fixture = ProcessInfo.processInfo.environment["COMMANDER_SFTP_FIXTURE"] else { throw XCTSkip("Owned loopback SFTP fixture required") }
        let root = URL(fileURLWithPath: fixture)
        let config = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("fixture.json"))) as! [String: Any]
        let dataRoot = root.appendingPathComponent("data/test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: false)
        try Data("SFTP fixture".utf8).write(to: dataRoot.appendingPathComponent("hello.txt"))
        defer { try? FileManager.default.removeItem(at: dataRoot) }
        var profile = ConnectionProfile(host: "127.0.0.1", port: config["port"] as! Int, username: config["username"] as! String,
                                        initialPath: dataRoot.path, authentication: .ed25519Key)
        profile.keyReference = try LocationResolver().reference(for: .local(root.appendingPathComponent("user_key")))
        let manager = SFTPConnectionManager()
        let socketsBefore = try fixtureSocketCount(port: profile.port)
        do { try await manager.connect(profile, secret: ""); XCTFail("Untrusted host must fail") }
        catch { XCTAssertTrue(error is HostKeyChallenge, "Expected host verification, got \(error)") }
        XCTAssertEqual(try fixtureSocketCount(port: profile.port), socketsBefore, "Rejected host verification must close its TCP transport")
        let verificationState = await manager.state(profile.id); XCTAssertEqual(verificationState, .verificationRequired)
        profile.serverKey = try String(contentsOf: root.appendingPathComponent("host_key.pub"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        try await manager.connect(profile, secret: "")
        let connectedState = await manager.state(profile.id); XCTAssertEqual(connectedState, .connected)
        let location = FileLocation.sftp(profileID: profile.id, path: try RemotePath(profile.initialPath))
        let listing = try await manager.list(location, options: .init())
        XCTAssertTrue(listing.entries.contains { $0.name == "hello.txt" })
        let original = try location.appending("hello.txt")
        let reader = try await manager.openFile(original, writeExclusive: false)
        let bytes = try await reader.read(offset: 0, length: 65536); try await reader.close()
        XCTAssertEqual(String(data: bytes, encoding: .utf8), "SFTP fixture")
        let uploaded = try location.appending("uploaded.txt")
        let writer = try await manager.openFile(uploaded, writeExclusive: true)
        try await writer.write(Data("uploaded fixture".utf8), offset: 0); try await writer.close()
        do { _ = try await manager.openFile(uploaded, writeExclusive: true); XCTFail("Exclusive create must refuse existing files") } catch { }
        let renamed = try location.appending("renamed.txt")
        try await manager.rename(uploaded, to: renamed)
        XCTAssertEqual(try String(contentsOf: dataRoot.appendingPathComponent("renamed.txt"), encoding: .utf8), "uploaded fixture")
        try await manager.createDirectory(try location.appending("new-folder"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dataRoot.appendingPathComponent("new-folder").path))
        do { _ = try await manager.list(try location.appending("missing"), options: .init()); XCTFail("Missing directory is not empty success") } catch { }
        let denied = dataRoot.appendingPathComponent("denied")
        try FileManager.default.createDirectory(at: denied, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: denied.path) }
        do { _ = try await manager.list(try location.appending("denied"), options: .init()); XCTFail("Denied directory is not empty success") }
        catch { XCTAssertTrue(error.localizedDescription.lowercased().contains("denied"), error.localizedDescription) }
        do { try await manager.rename(renamed, to: original); XCTFail("Rename must not overwrite an existing item") } catch { }
        XCTAssertEqual(try String(contentsOf: dataRoot.appendingPathComponent("hello.txt"), encoding: .utf8), "SFTP fixture")
        let local = try FixtureDirectory(); let source = try local.file("round trip #中文.bin", content: String(repeating: "SFTP bytes", count: 20_000))
        let localDestination = try local.directory("download")
        let executor = RemoteTransferExecutor(remote: manager, journal: .init(directory: local.url.appendingPathComponent("journal")))
        let up = await executor.executeRequest(.init(kind: .copy, sources: [.local(source)], destinationDirectory: location), cancellation: .init(), resolveConflict: { _ in .init(.skip) }, emit: { _ in })
        XCTAssertEqual(up.state, .completed, up.outcomes.first?.detail ?? "")
        let down = await executor.executeRequest(.init(kind: .copy, sources: [try location.appending(source.lastPathComponent)], destinationDirectory: .local(localDestination)), cancellation: .init(), resolveConflict: { _ in .init(.skip) }, emit: { _ in })
        XCTAssertEqual(down.state, .completed, down.outcomes.first?.detail ?? "")
        XCTAssertEqual(try Data(contentsOf: source), try Data(contentsOf: localDestination.appendingPathComponent(source.lastPathComponent)))
        try await assertNetworkTreeRoundTrip(remote: manager, root: location)
        await manager.disconnect(profile.id)
        let disconnectedState = await manager.state(profile.id); XCTAssertEqual(disconnectedState, .disconnected)
        do { _ = try await manager.list(location, options: .init()); XCTFail("Disconnected listing must fail") } catch { }
        let canceledAttempt = UUID(); let successorAttempt = UUID()
        try await manager.connect(profile, secret: "", attempt: canceledAttempt)
        await manager.cancelAttempt(canceledAttempt)
        try await manager.connect(profile, secret: "", attempt: successorAttempt)
        await manager.cancelAttempt(canceledAttempt)
        let successorStillConnected = await manager.isConnected(profile.id)
        XCTAssertTrue(successorStillConnected, "A stale editor cancellation cannot disconnect a newer attempt")
        _ = try await manager.list(location, options: .init())
        await manager.disconnect(profile.id)
        profile.serverKey = "ssh-ed25519 Y2hhbmdlZA=="
        let restoredManager = SFTPConnectionManager()
        do { try await restoredManager.connect(profile, secret: ""); XCTFail("Changed key must fail") }
        catch { XCTAssertNotNil((error as? HostKeyChallenge)?.previousFingerprint) }
    }
    func testStalledPeerTimeoutReleasesQueueGate() async throws {
        try await exerciseStalledPeer(cancel: false)
    }
    func testCancelInterruptsStalledPeerAndReleasesQueueGate() async throws {
        try await exerciseStalledPeer(cancel: true)
    }
    private func exerciseStalledPeer(cancel: Bool) async throws {
        guard let fixture = ProcessInfo.processInfo.environment["COMMANDER_SFTP_FIXTURE"] else { throw XCTSkip("Owned loopback SFTP fixture required") }
        let root = URL(fileURLWithPath: fixture)
        let config = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("fixture.json"))) as! [String: Any]
        let f = try FixtureDirectory()
        let source = try f.file("stalled.bin", content: String(repeating: "owned bytes", count: 50_000))
        let localDestination = try f.directory("local-output")
        let remoteDirectory = root.appendingPathComponent("data/stall-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: remoteDirectory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: remoteDirectory) }
        var profile = ConnectionProfile(host: "127.0.0.1", port: config["port"] as! Int, username: config["username"] as! String, initialPath: remoteDirectory.path, authentication: .ed25519Key)
        profile.keyReference = try LocationResolver().reference(for: .local(root.appendingPathComponent("user_key")))
        profile.serverKey = try String(contentsOf: root.appendingPathComponent("host_key.pub"), encoding: .utf8)
        let manager = SFTPConnectionManager(operationTimeout: cancel ? .seconds(10) : .milliseconds(150))
        try await manager.connect(profile, secret: "")
        let owned = try OwnedStoppedSSHPeer(root: root)
        defer { owned.resume() }
        let executor = RemoteTransferExecutor(remote: manager, journal: .init(directory: f.url.appendingPathComponent("journal")))
        let stopping = StopPeerExecutor(base: executor, peer: owned)
        let queue = TransferQueue(executor: stopping)
        let remote = FileLocation.sftp(profileID: profile.id, path: try RemotePath(remoteDirectory.path))
        let first = await queue.enqueue(.init(kind: .copy, sources: [.local(source)], destinationDirectory: remote))
        let next = await queue.enqueue(.init(kind: .copy, sources: [.local(source)], destinationDirectory: .local(localDestination)))
        let stopDeadline = ContinuousClock.now + .seconds(3)
        while !owned.isStopped && ContinuousClock.now < stopDeadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(owned.isStopped, "The owned peer must stop during a pending streamed write")
        if cancel { await queue.cancel(jobID: first) }
        let deadline = ContinuousClock.now + .seconds(1)
        var finished = false
        while ContinuousClock.now < deadline {
            let jobs = await queue.currentSnapshots()
            finished = jobs.first(where: { $0.id == first })?.state.isTerminal == true && jobs.first(where: { $0.id == next })?.state == .completed
            if finished { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(finished, "Timeout/cancel must hard-close a stalled transport and release the shared gate")
        let observed = await queue.currentSnapshots()
        let firstOutcome = observed.first { $0.id == first }
        XCTAssertNotEqual(firstOutcome?.state, .completed, "A stopped peer cannot finish the upload: \(firstOutcome?.outcomes.map { $0.detail ?? "" } ?? [])")
        let connected = await manager.isConnected(profile.id)
        XCTAssertFalse(connected, "A stalled session must lose its owned TCP transport")
        owned.resume()
        await manager.disconnect(profile.id)
        let cleanupDeadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < cleanupDeadline {
            if await queue.currentSnapshots().allSatisfy({ $0.state.isTerminal }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(try Data(contentsOf: source), try Data(contentsOf: localDestination.appendingPathComponent(source.lastPathComponent)))
    }
    private func fixtureSocketCount(port: Int) throws -> Int {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-a", "-p", String(ProcessInfo.processInfo.processIdentifier), "-iTCP:\(port)"]
        let output = Pipe(); process.standardOutput = output; process.standardError = Pipe()
        try process.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        return max(0, String(decoding: data, as: UTF8.self).split(separator: "\n").count - 1)
    }

}

private final class OwnedStoppedSSHPeer: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private var pids: [pid_t] = []
    private let master: pid_t
    init(root: URL) throws {
        master = Int32(try String(contentsOf: root.appendingPathComponent("sshd.pid"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
    }
    private func currentChildren() throws -> [pid_t] {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/ps"); process.arguments = ["-axo", "pid=,ppid="]
        let output = Pipe(); process.standardOutput = output; try process.run()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self); process.waitUntilExit()
        let pairs = text.split(separator: "\n").compactMap { line -> (Int32, Int32)? in
            let ids = line.split(whereSeparator: { $0.isWhitespace }).compactMap { Int32($0) }; return ids.count == 2 ? (ids[0], ids[1]) : nil
        }
        var owned: Set<Int32> = [master]
        while true { let expanded = owned.union(pairs.filter { owned.contains($0.1) }.map(\.0)); if expanded == owned { break }; owned = expanded }
        owned.remove(master); return Array(owned)
    }
    var isStopped: Bool { lock.withLock { stopped } }
    func stopOnce() { lock.withLock {
        guard !stopped, let children = try? currentChildren(), !children.isEmpty else { return }
        pids = children; for pid in pids { _ = kill(pid, SIGSTOP) }; stopped = true
    } }
    func resume() { lock.withLock { for pid in pids { _ = kill(pid, SIGCONT) } } }
}
private struct StopPeerExecutor: TransferExecuting {
    let base: RemoteTransferExecutor
    let peer: OwnedStoppedSSHPeer
    func execute(_ plan: TransferPlan, cancellation: OperationCancellation, resolveConflict: @escaping @Sendable (TransferConflict) async -> ConflictResolution, emit: @escaping @Sendable (OperationEvent) -> Void) async -> OperationResult {
        await base.execute(plan, cancellation: cancellation, resolveConflict: resolveConflict, emit: emit)
    }
    func executeRequest(_ request: TransferRequest, cancellation: OperationCancellation, resolveConflict: @escaping @Sendable (TransferConflict) async -> ConflictResolution, emit: @escaping @Sendable (OperationEvent) -> Void) async -> OperationResult {
        await base.executeRequest(request, cancellation: cancellation, resolveConflict: resolveConflict, emit: { event in
            if case .progress(let progress) = event, progress.bytesCopied > 0, !request.destinationDirectory.isLocal { peer.stopOnce() }
            emit(event)
        })
    }
}
