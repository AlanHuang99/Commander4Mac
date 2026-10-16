import XCTest
import CommanderCore

final class TransferQueueTests: XCTestCase, @unchecked Sendable {
    func testSerialQueueCapturesDestinationAndCanceledQueuedJobNeverExecutes() async throws {
        let f = try FixtureDirectory(); let a = try f.file("a"); let b = try f.file("b"); let d = try f.directory("destination")
        let executor = HeldExecutor()
        let queue = TransferQueue(executor: executor)
        let first = TransferRequest(kind: .copy, sources: [.local(a)], destinationDirectory: .local(d))
        let second = TransferRequest(kind: .move, sources: [.local(b)], destinationDirectory: .local(d))
        _ = await queue.enqueue(first)
        try await eventually { await executor.startedCount == 1 }
        _ = await queue.enqueue(second)
        await queue.cancel(jobID: second.id)
        await executor.release()
        try await eventually { await queue.currentSnapshots().first?.state == .completed }
        let requests = await executor.requests
        let maximum = await executor.maximum
        XCTAssertEqual(requests.map(\.id), [first.id])
        XCTAssertEqual(requests.first?.destinationDirectory, .local(d))
        XCTAssertEqual(maximum, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: d.path).isEmpty)
    }
    func testConflictRequiresMatchingJobAndConflictAndApplyAllResetsPerJob() async throws {
        let f = try FixtureDirectory(); let a = try f.file("a"); let b = try f.file("b"); let d = try f.directory("dest")
        try Data("old".utf8).write(to: d.appendingPathComponent("a")); try Data("old".utf8).write(to: d.appendingPathComponent("b"))
        let queue = TransferQueue(executor: LocalOperationExecutor(journal: .init(directory: f.url.appendingPathComponent("journal"))))
        let first = TransferRequest(kind: .copy, sources: [.local(a), .local(b)], destinationDirectory: .local(d))
        _ = await queue.enqueue(first)
        try await eventually { await queue.currentSnapshots().first?.pendingConflict != nil }
        let waitingConflict = await queue.currentSnapshots().first?.pendingConflict
        let conflict = try XCTUnwrap(waitingConflict)
        await queue.resolveConflict(jobID: UUID(), conflictID: conflict.id, resolution: .init(.replace))
        await queue.resolveConflict(jobID: first.id, conflictID: UUID(), resolution: .init(.replace))
        let waiting = await queue.currentSnapshots().first?.state
        XCTAssertEqual(waiting, .awaitingConflict)
        await queue.resolveConflict(jobID: first.id, conflictID: conflict.id, resolution: .init(.skip, applyToAll: true))
        try await eventually { await queue.currentSnapshots().first?.state == .completed }
        let second = TransferRequest(kind: .copy, sources: [.local(a)], destinationDirectory: .local(d))
        _ = await queue.enqueue(second)
        try await eventually { await queue.currentSnapshots().last?.pendingConflict != nil }
        await queue.cancel(jobID: second.id)
        try await eventually { await queue.currentSnapshots().last?.state == .canceled }
        XCTAssertEqual(try String(contentsOf: d.appendingPathComponent("a"), encoding: .utf8), "old")
    }
    func testTwoJobsNeverExecuteTogether() async throws {
        let f = try FixtureDirectory(); let a = try f.file("a"); let d = try f.directory("dest")
        let executor = HeldExecutor(); let queue = TransferQueue(executor: executor)
        _ = await queue.enqueue(.init(kind: .copy, sources: [.local(a)], destinationDirectory: .local(d)))
        _ = await queue.enqueue(.init(kind: .copy, sources: [.local(a)], destinationDirectory: .local(d)))
        try await eventually { await executor.startedCount == 1 }
        await executor.release()
        try await eventually { await executor.startedCount == 2 }
        await executor.release()
        try await eventually { await queue.currentSnapshots().allSatisfy { $0.state.isTerminal } }
        let maximum = await executor.maximum
        XCTAssertEqual(maximum, 1)
    }
}
private actor HeldExecutor: TransferExecuting {
    var requests: [TransferRequest] = []
    var maximum = 0
    var active = 0
    var continuation: CheckedContinuation<Void, Never>?
    var startedCount: Int { requests.count }
    func release() { continuation?.resume(); continuation = nil }
    func execute(_ plan: TransferPlan, cancellation: OperationCancellation,
                 resolveConflict: @escaping @Sendable (TransferConflict) async -> ConflictResolution,
                 emit: @escaping @Sendable (OperationEvent) -> Void) async -> OperationResult {
        active += 1; maximum = max(maximum, active); requests.append(plan.request)
        await withCheckedContinuation { continuation = $0 }
        active -= 1
        return .init(jobID: plan.request.id, outcomes: [], state: .completed)
    }
}
private func eventually(_ condition: @escaping @Sendable () async -> Bool) async throws {
    for _ in 0..<200 {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Timed out waiting for queue state")
    throw CancellationError()
}
