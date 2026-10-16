import XCTest
import CommanderCore

final class LocalOperationExecutorTests: XCTestCase, @unchecked Sendable {
    func testMoveRetainsSourceWhenFinalDestinationDisappears() async throws {
        let f = try FixtureDirectory(); let source = try f.file("move.txt"); let dest = try f.directory("dest")
        let result = try await execute(.move, source: source, destination: dest,
            backend: FinalDestinationMutatingBackend(change: .removeRoot))
        XCTAssertEqual(result.outcomes.first?.state, .partial)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent("move.txt").path))
    }
    func testMoveRetainsTreeWhenFinalDestinationChildDisappearsOrIsReplaced() async throws {
        for change in [FinalDestinationMutatingBackend.Change.removeChild, .replaceChild] {
            let f = try FixtureDirectory(); let source = try f.directory("tree"); let dest = try f.directory("dest")
            try Data("original child".utf8).write(to: source.appendingPathComponent("child"))
            let result = try await execute(.move, source: source, destination: dest,
                backend: FinalDestinationMutatingBackend(change: change))
            XCTAssertEqual(result.outcomes.first?.state, .partial)
            XCTAssertEqual(try String(contentsOf: source.appendingPathComponent("child"), encoding: .utf8), "original child")
            if change == .replaceChild {
                XCTAssertEqual(try String(contentsOf: dest.appendingPathComponent("tree/child"), encoding: .utf8), "external replacement")
            }
        }
    }
    func testMoveRetainsSourceWhenFinalDestinationParentIsReplaced() async throws {
        let f = try FixtureDirectory(); let source = try f.file("move.txt"); let dest = try f.directory("dest")
        let result = try await execute(.move, source: source, destination: dest,
            backend: FinalDestinationMutatingBackend(change: .replaceParent))
        XCTAssertEqual(result.outcomes.first?.state, .partial)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testAtomicMoveRejectsDestinationReplacementDuringConflictDecision() async throws {
        let f = try FixtureDirectory(); let source = try f.file("move.txt"); let dest = try f.directory("dest")
        try Data("existing".utf8).write(to: dest.appendingPathComponent("move.txt"))
        let plan = try LocalTransferPlanner().plan(.init(kind: .move, sources: [.local(source)], destinationDirectory: .local(dest)))
        let detached = f.url.appendingPathComponent("old-dest")
        let executor = LocalOperationExecutor(journal: .init(directory: f.url.appendingPathComponent("journal")))
        let result = await executor.execute(plan, cancellation: .init(), resolveConflict: { _ in
            do {
                try FileManager.default.moveItem(at: dest, to: detached)
                try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: false)
            } catch { XCTFail("Fixture setup failed: \(error)") }
            return .init(.keepBoth)
        }, emit: { _ in })
        XCTAssertEqual(result.state, .failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dest.path).isEmpty)
        XCTAssertEqual(try String(contentsOf: detached.appendingPathComponent("move.txt"), encoding: .utf8), "existing")
    }
    private func execute(_ kind: TransferKind = .copy, source: URL, destination: URL, decision: ConflictDecision = .skip,
                         backend: any FileOperationBackend = SystemFileOperationBackend(),
                         copier: any FileCopying = LocalCopyEngine(), cancellation: OperationCancellation = .init()) async throws -> OperationResult {
        let plan = try LocalTransferPlanner().plan(.init(kind: kind, sources: [.local(source)], destinationDirectory: .local(destination)))
        let executor = LocalOperationExecutor(journal: OperationJournal(directory: destination.deletingLastPathComponent().appendingPathComponent(".journal")), backend: backend, copier: copier)
        return await executor.execute(plan, cancellation: cancellation, resolveConflict: { _ in .init(decision) }, emit: { _ in })
    }
    func testOccupiedStagingPathIsNeverRemoved() async throws {
        let f = try FixtureDirectory(); let source = try f.file("source"); let dest = try f.directory("dest")
        let plan = try LocalTransferPlanner().plan(.init(kind: .copy, sources: [.local(source)], destinationDirectory: .local(dest)))
        let occupied = dest.appendingPathComponent(".commander4mac-" + plan.items[0].id.uuidString + ".partial")
        try FileManager.default.createDirectory(at: occupied, withIntermediateDirectories: false)
        let sentinel = occupied.appendingPathComponent("unrelated")
        try Data("must survive".utf8).write(to: sentinel)
        let executor = LocalOperationExecutor(journal: .init(directory: f.url.appendingPathComponent("journal")))
        let result = await executor.execute(plan, cancellation: .init(), resolveConflict: { _ in .init(.skip) }, emit: { _ in })
        XCTAssertEqual(result.state, .failed)
        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "must survive")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
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

private struct FinalDestinationMutatingBackend: FileOperationBackend {
    enum Change { case removeRoot, removeChild, replaceChild, replaceParent }
    let change: Change
    private let system = SystemFileOperationBackend()
    func version(at url: URL) throws -> ItemVersion { try system.version(at: url) }
    func supportsAtomicMove(from source: URL, to destination: URL) -> Bool { false }
    func renameExclusive(from source: URL, to destination: URL) throws {
        try system.renameExclusive(from: source, to: destination)
        try mutate(destination)
    }
    func swap(_ first: URL, _ second: URL) throws { try system.swap(first, second); try mutate(second) }
    func removeSource(at url: URL, expecting version: ItemVersion) throws { try system.removeSource(at: url, expecting: version) }
    private func mutate(_ destination: URL) throws {
        switch change {
        case .removeRoot: try FileManager.default.removeItem(at: destination)
        case .removeChild: try FileManager.default.removeItem(at: destination.appendingPathComponent("child"))
        case .replaceChild: try Data("external replacement".utf8).write(to: destination.appendingPathComponent("child"), options: .atomic)
        case .replaceParent:
            let parent = destination.deletingLastPathComponent()
            try FileManager.default.moveItem(at: parent, to: parent.appendingPathExtension("detached"))
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        }
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
