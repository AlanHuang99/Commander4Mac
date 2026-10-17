// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import XCTest
import CommanderCore

@MainActor final class SessionPersistenceTests: XCTestCase {
    func testBookmarkWorkRunsOffMainActorAndDoesNotBlockSessionCaptureOrRestore() async throws {
        let f = try FixtureDirectory()
        let workspace = WorkspaceSession(left: .local(f.url), right: .local(f.url))
        let resolver = PausingLocationResolver()
        let persistence = SessionPersistence(store: .init(directory: f.url.appendingPathComponent("state")), resolver: resolver)
        let snapshot = try WorkspaceSnapshot(workspace)
        let task = Task { try await persistence.save(.init(windows: [snapshot]), revision: 1) }
        for _ in 0..<200 where !resolver.hasStarted { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(resolver.hasStarted)
        // This executes on the main actor while the filesystem worker is paused.
        let otherSnapshot = try WorkspaceSnapshot(workspace)
        XCTAssertEqual(otherSnapshot.restore().left.activeTab.location, .local(f.url))
        resolver.release()
        let savedResult = try await task.value
        let saved = try XCTUnwrap(savedResult)
        XCTAssertFalse(resolver.calledOnMainThread)
        XCTAssertFalse(try XCTUnwrap(saved.windows.first).restore().left.activeTab.unresolvedReference!.bookmark.isEmpty)
    }
    func testUnavailableReferenceRefreshPreservesLastValidBookmark() async throws {
        let f = try FixtureDirectory()
        let location = FileLocation.local(try f.directory("folder"))
        let reference = try LocationResolver().reference(for: location)
        let workspace = WorkspaceSession(left: location, right: location)
        workspace.left.activeTab.savedReference = reference
        let persistence = SessionPersistence(store: .init(directory: f.url.appendingPathComponent("state")), resolver: FailingLocationResolver())
        let snapshot = try WorkspaceSnapshot(workspace)
        let result = try await persistence.save(.init(windows: [snapshot]), revision: 2)
        let restored = try XCTUnwrap(result?.windows.first).restore()
        XCTAssertEqual(restored.left.activeTab.unresolvedReference, reference)
        let stale = try await persistence.save(.init(), revision: 1)
        XCTAssertNil(stale)
    }
}

private final class PausingLocationResolver: LocationResolving, @unchecked Sendable {
    private let lock = NSLock()
    private let signal = DispatchSemaphore(value: 0)
    private var started = false
    private var mainThread = false
    var hasStarted: Bool { lock.withLock { started } }
    var calledOnMainThread: Bool { lock.withLock { mainThread } }
    func release() { signal.signal() }
    func reference(for location: FileLocation) throws -> LocationReference {
        let pause = lock.withLock { () -> Bool in
            mainThread = mainThread || Thread.isMainThread
            let first = !started; started = true; return first
        }
        if pause { _ = signal.wait(timeout: .now() + 3) }
        return try LocationResolver().reference(for: location)
    }
    func resolve(_ reference: LocationReference) -> ResolvedLocation { LocationResolver().resolve(reference) }
}
private struct FailingLocationResolver: LocationResolving {
    func reference(for location: FileLocation) throws -> LocationReference { throw CocoaError(.fileReadNoPermission) }
    func resolve(_ reference: LocationReference) -> ResolvedLocation { .unavailable("offline") }
}
