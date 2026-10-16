import XCTest
import CommanderCore

final class LocalOperationExecutorTests: XCTestCase, @unchecked Sendable {
    private func execute(_ kind: TransferKind = .copy, source: URL, destination: URL, decision: ConflictDecision = .skip,
                         backend: any FileOperationBackend = SystemFileOperationBackend(),
                         copier: any FileCopying = LocalCopyEngine(), cancellation: OperationCancellation = .init()) async throws -> OperationResult {
        let plan = try LocalTransferPlanner().plan(.init(kind: kind, sources: [.local(source)], destinationDirectory: .local(destination)))
        let executor = LocalOperationExecutor(journal: OperationJournal(directory: destination.deletingLastPathComponent().appendingPathComponent(".journal")), backend: backend, copier: copier)
        return await executor.execute(plan, cancellation: cancellation, resolveConflict: { _ in .init(decision) }, emit: { _ in })
    }
    func testCopyKeepsSourceAndFinalizesCompleteContents() async throws {
        let f = try FixtureDirectory(); let source = try f.file("file.txt", content: "complete contents"); let dest = try f.directory("dest")
        let result = try await execute(source: source, destination: dest)
        XCTAssertEqual(result.state, .completed)
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("file.txt"), encoding: .utf8), "complete contents")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: dest.path).contains { $0.hasPrefix(".commander4mac-") })
    }
    func testSameVolumeMoveRemovesOnlyTheSource() async throws {
        let f = try FixtureDirectory(); let source = try f.file("move.txt"); let dest = try f.directory("dest")
        let result = try await execute(.move, source: source, destination: dest)
        XCTAssertEqual(result.state, .completed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("move.txt"), encoding: .utf8), "fixture")
    }
    func testSkipKeepsExistingDestination() async throws {
        let f = try FixtureDirectory(); let source = try f.file("same.txt", content: "new"); let dest = try f.directory("dest")
        try Data("old".utf8).write(to: dest.appendingPathComponent("same.txt"))
        let result = try await execute(source: source, destination: dest, decision: .skip)
        XCTAssertEqual(result.outcomes.first?.state, .skipped)
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("same.txt"), encoding: .utf8), "old")
    }
    func testKeepBothAndReplaceUseExplicitPolicy() async throws {
        let f = try FixtureDirectory(); let source = try f.file("same.txt", content: "new"); let dest = try f.directory("dest")
        let target = dest.appendingPathComponent("same.txt"); try Data("old".utf8).write(to: target)
        let kept = try await execute(source: source, destination: dest, decision: .keepBoth)
        XCTAssertEqual(kept.state, .completed)
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("same copy.txt"), encoding: .utf8), "new")
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "old")
        let replaced = try await execute(source: source, destination: dest, decision: .replace)
        XCTAssertEqual(replaced.state, .completed)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "new")
    }
    func testCanceledBeforeStartDoesNotMutateEitherTree() async throws {
        let f = try FixtureDirectory(); let source = try f.file("cancel.txt"); let dest = try f.directory("dest")
        let token = OperationCancellation(); token.cancel()
        let result = try await execute(.move, source: source, destination: dest, cancellation: token)
        XCTAssertEqual(result.state, .canceled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dest.path).isEmpty)
    }
    func testCopyFailureLeavesOldDestinationAndSourceUntouched() async throws {
        let f = try FixtureDirectory(); let source = try f.file("same.txt", content: "new"); let dest = try f.directory("dest")
        try Data("old".utf8).write(to: dest.appendingPathComponent("same.txt"))
        let result = try await execute(.move, source: source, destination: dest, decision: .replace, copier: FailingCopier())
        XCTAssertEqual(result.state, .failed)
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("same.txt"), encoding: .utf8), "old")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testRacingDestinationIsPreservedWhenUserSkipsNewConflict() async throws {
        let f = try FixtureDirectory(); let source = try f.file("race.txt", content: "new"); let dest = try f.directory("dest")
        let backend = FaultInjectingFileOperations(raceDestination: dest.appendingPathComponent("race.txt"))
        let result = try await execute(source: source, destination: dest, backend: backend)
        XCTAssertEqual(result.outcomes.first?.state, .skipped)
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("race.txt"), encoding: .utf8), "racing writer")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testCopyThenRemoveFailureReportsPartialAndKeepsSource() async throws {
        let f = try FixtureDirectory(); let source = try f.file("move.txt"); let dest = try f.directory("dest")
        let backend = FaultInjectingFileOperations(simulateCrossVolume: true, failRemoval: true)
        let result = try await execute(.move, source: source, destination: dest, backend: backend)
        XCTAssertEqual(result.outcomes.first?.state, .partial)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("move.txt"), encoding: .utf8), "fixture")
    }
    func testNestedSourceMutationDuringCopyRetainsSourceAndDoesNotFinalize() async throws {
        let f = try FixtureDirectory(); let source = try f.directory("tree"); let child = source.appendingPathComponent("child.txt")
        try Data("before".utf8).write(to: child); let dest = try f.directory("dest")
        let result = try await execute(.move, source: source, destination: dest,
            backend: FaultInjectingFileOperations(simulateCrossVolume: true), copier: MutatingCopier(child: child))
        XCTAssertEqual(result.state, .failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: child.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent("tree").path))
    }
    func testJournalFailurePreventsAllMutations() async throws {
        let f = try FixtureDirectory(); let source = try f.file("source.txt"); let dest = try f.directory("dest")
        let blocked = try f.file("not-a-directory")
        let executor = LocalOperationExecutor(journal: OperationJournal(directory: blocked))
        let plan = try LocalTransferPlanner().plan(.init(kind: .move, sources: [.local(source)], destinationDirectory: .local(dest)))
        let result = await executor.execute(plan, cancellation: .init(), resolveConflict: { _ in .init(.skip) }, emit: { _ in })
        XCTAssertEqual(result.state, .failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dest.path).isEmpty)
    }
    func testChangedDestinationAfterConfirmationIsNotReplaced() async throws {
        let f = try FixtureDirectory(); let source = try f.file("same.txt", content: "new"); let dest = try f.directory("dest")
        let target = dest.appendingPathComponent("same.txt"); try Data("old".utf8).write(to: target)
        let result = try await execute(source: source, destination: dest, decision: .replace, copier: DestinationMutatingCopier(target: target))
        XCTAssertEqual(result.state, .failed)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "external update")
    }
    func testDisconnectedDestinationRetainsSourceAndReportsFailure() async throws {
        let f = try FixtureDirectory(); let source = try f.file("source.txt"); let dest = try f.directory("dest")
        let detached = f.url.appendingPathComponent("detached")
        let result = try await execute(.move, source: source, destination: dest,
            backend: FaultInjectingFileOperations(simulateCrossVolume: true), copier: DisconnectingCopier(destination: dest, detached: detached))
        XCTAssertEqual(result.state, .failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: detached.appendingPathComponent("source.txt").path))
    }
    func testCanceledCopyNeverFinalizesPartialDestination() async throws {
        let f = try FixtureDirectory(); let source = f.url.appendingPathComponent("large.bin")
        try Data(repeating: 0x6b, count: 8 * 1024 * 1024).write(to: source)
        let dest = try f.directory("dest"); let token = OperationCancellation()
        let copier = CancelingCopier(token: token)
        let result = try await execute(source: source, destination: dest, copier: copier, cancellation: token)
        XCTAssertEqual(result.state, .canceled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent("large.bin").path))
    }
}

private struct FailingCopier: FileCopying {
    func copy(source: URL, stagingDestination: URL, cancellation: OperationCancellation, progress: @escaping @Sendable (CopyProgress) -> Void) throws {
        try Data("partial".utf8).write(to: stagingDestination)
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
    }
}
private struct MutatingCopier: FileCopying {
    let child: URL
    func copy(source: URL, stagingDestination: URL, cancellation: OperationCancellation, progress: @escaping @Sendable (CopyProgress) -> Void) throws {
        try LocalCopyEngine().copy(source: source, stagingDestination: stagingDestination, cancellation: cancellation, progress: progress)
        try Data("changed during copy".utf8).write(to: child)
    }
}
private struct CancelingCopier: FileCopying {
    let token: OperationCancellation
    func copy(source: URL, stagingDestination: URL, cancellation: OperationCancellation, progress: @escaping @Sendable (CopyProgress) -> Void) throws {
        try LocalCopyEngine().copy(source: source, stagingDestination: stagingDestination, cancellation: cancellation) { value in
            token.cancel(); progress(value)
        }
    }
}

private struct DestinationMutatingCopier: FileCopying {
    let target: URL
    func copy(source: URL, stagingDestination: URL, cancellation: OperationCancellation, progress: @escaping @Sendable (CopyProgress) -> Void) throws {
        try LocalCopyEngine().copy(source: source, stagingDestination: stagingDestination, cancellation: cancellation, progress: progress)
        try Data("external update".utf8).write(to: target, options: .atomic)
    }
}

private struct DisconnectingCopier: FileCopying {
    let destination: URL
    let detached: URL
    func copy(source: URL, stagingDestination: URL, cancellation: OperationCancellation, progress: @escaping @Sendable (CopyProgress) -> Void) throws {
        try LocalCopyEngine().copy(source: source, stagingDestination: stagingDestination, cancellation: cancellation, progress: progress)
        try FileManager.default.moveItem(at: destination, to: detached)
    }
}
