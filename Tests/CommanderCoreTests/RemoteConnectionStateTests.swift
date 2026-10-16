import XCTest
@testable import CommanderCore

final class RemoteConnectionStateTests: XCTestCase, @unchecked Sendable {
    func testDisconnectBeforeConnectReturnsCannotPublishConnected() async throws {
        let transport = ReorderedConnectionTransport()
        let manager = RemoteConnectionManager(sftp: transport, smb: transport, webdav: transport)
        let stream = await manager.snapshots(); var states = stream.makeAsyncIterator(); _ = await states.next()
        let profile = ConnectionProfile(host: "127.0.0.1", username: "owned")
        do {
            try await manager.connect(profile, secret: "closed")
            XCTFail("A transport that closed during connect must not report success")
        } catch { XCTAssertFalse(error is CancellationError) }
        let latest = await states.next(); XCTAssertEqual(latest?[profile.id], .failed)
        let connected = await manager.isConnected(profile.id); XCTAssertFalse(connected)
    }
    func testOldFailureCannotOverwriteNewConnectedState() async throws {
        let transport = ReorderedConnectionTransport()
        let manager = RemoteConnectionManager(sftp: transport, smb: transport, webdav: transport)
        let stream = await manager.snapshots(); var states = stream.makeAsyncIterator(); _ = await states.next()
        var profile = ConnectionProfile(host: "127.0.0.1", username: "owned"); profile.protocolKind = .webdav
        let p = profile; let old = Task { try await manager.connect(p, secret: "old") }
        try await waitForPending(transport)
        try await manager.connect(p, secret: "new")
        await transport.failPending(); _ = await old.result
        let latest = await states.next(); XCTAssertEqual(latest?[p.id], .connected)
        let connected = await manager.isConnected(p.id); XCTAssertTrue(connected)
    }
    func testOldFailureCannotOverwriteExplicitDisconnect() async throws {
        let transport = ReorderedConnectionTransport()
        let manager = RemoteConnectionManager(sftp: transport, smb: transport, webdav: transport)
        let stream = await manager.snapshots(); var states = stream.makeAsyncIterator(); _ = await states.next()
        var profile = ConnectionProfile(host: "127.0.0.1", username: "owned"); profile.protocolKind = .webdav
        let p = profile; let old = Task { try await manager.connect(p, secret: "old") }
        try await waitForPending(transport)
        await manager.disconnect(p.id); await transport.failPending(); _ = await old.result
        let latest = await states.next(); XCTAssertEqual(latest?[p.id], .disconnected)
    }
    private func waitForPending(_ transport: ReorderedConnectionTransport) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await transport.hasPending) && .now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        let pending = await transport.hasPending; XCTAssertTrue(pending)
    }
}

private actor ReorderedConnectionTransport: RemoteConnectionTransport {
    private var pending: CheckedContinuation<Void, any Error>?
    private var connected = false
    private var observer: AsyncStream<[UUID: SFTPConnectionState]>.Continuation?
    func snapshots() -> AsyncStream<[UUID: SFTPConnectionState]> {
        let (stream, continuation) = AsyncStream<[UUID: SFTPConnectionState]>.makeStream(bufferingPolicy: .bufferingNewest(1))
        observer = continuation; return stream
    }
    var hasPending: Bool { pending != nil }
    func connect(_ profile: ConnectionProfile, secret: String, attempt: UUID) async throws {
        if secret == "old" { try await withCheckedThrowingContinuation { pending = $0 } }
        else if secret == "closed" { connected = false; observer?.yield([profile.id: .disconnected]) }
        else { connected = true }
    }
    func failPending() { pending?.resume(throwing: FileOperationError.message("Owned delayed network failure")); pending = nil }
    func disconnect(_ id: UUID) { connected = false }
    func cancelAttempt(_ attempt: UUID) {}
    func isConnected(_ id: UUID) -> Bool { connected }
    func list(_ location: FileLocation, options: ListingOptions) async throws -> DirectorySnapshot { .init(location: location, entries: []) }
    func metadata(_ location: FileLocation) async throws -> RemoteFileMetadata? { nil }
    func openFile(_ location: FileLocation, writeExclusive: Bool) async throws -> any RemoteFileChannel { throw CancellationError() }
    func rename(_ source: FileLocation, to destination: FileLocation) async throws { throw CancellationError() }
    func createDirectory(_ location: FileLocation) async throws { throw CancellationError() }
}
