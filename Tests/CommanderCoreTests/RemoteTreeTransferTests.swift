import XCTest
import CommanderCore

final class RemoteTreeTransferTests: XCTestCase, @unchecked Sendable {
    private func run(_ source: FileLocation, to destination: FileLocation, remote: TreeMemoryRemote, journal: URL, decision: ConflictDecision = .skip, token: OperationCancellation = .init()) async -> OperationResult {
        await RemoteTransferExecutor(remote: remote, journal: .init(directory: journal)).executeRequest(.init(kind: .copy, sources: [source], destinationDirectory: destination), cancellation: token, resolveConflict: { conflict in XCTAssertTrue(conflict.isDirectory); XCTAssertFalse(conflict.supportsReplacement); return .init(decision) }, emit: { _ in })
    }
    func testNestedEmptyAndUnicodeTreesRoundTripAndRootConflicts() async throws {
        let f = try FixtureDirectory(); let source = try f.directory("tree #中文"); try FileManager.default.createDirectory(at: source.appendingPathComponent("empty"), withIntermediateDirectories: false)
        let nested = source.appendingPathComponent("nested"); try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try Data("tree bytes".utf8).write(to: nested.appendingPathComponent("literal #%$.txt"))
        let remote = TreeMemoryRemote(); let root = remote.root; let target = try root.appending(source.lastPathComponent)
        let up = await run(.local(source), to: root, remote: remote, journal: f.url.appendingPathComponent("journal")); XCTAssertEqual(up.state, .completed, up.outcomes.first?.detail ?? "")
        let bytes = await remote.data(try target.appending("nested").appending("literal #%$.txt")); XCTAssertEqual(bytes, Data("tree bytes".utf8))
        let downloads = try f.directory("downloads"); let down = await run(target, to: .local(downloads), remote: remote, journal: f.url.appendingPathComponent("journal")); XCTAssertEqual(down.state, .completed, down.outcomes.first?.detail ?? "")
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloads.appendingPathComponent(source.lastPathComponent + "/empty").path))
        let skipped = await run(.local(source), to: root, remote: remote, journal: f.url.appendingPathComponent("journal")); XCTAssertEqual(skipped.outcomes.first?.state, .skipped)
        let both = await run(.local(source), to: root, remote: remote, journal: f.url.appendingPathComponent("journal"), decision: .keepBoth); XCTAssertEqual(both.state, .completed, both.outcomes.first?.detail ?? "")
        let kept = try await remote.metadata(root.appending(source.lastPathComponent + " copy")); XCTAssertEqual(kept?.kind, .directory)
    }
    func testPlannerRejectsLinksPackagesAndBoundsBeforeAnyMutation() async throws {
        let f = try FixtureDirectory(); let folder = try f.directory("folder"); let file = try f.file("folder/file"); let remote = TreeMemoryRemote()
        let planner = TransferTreePlanner(remote: remote, maxEntries: 1, maxDepth: 128)
        do { _ = try await planner.plan(.local(folder)); XCTFail("Entry bound") } catch { }
        let deep = try f.directory("folder/deep")
        do { _ = try await TransferTreePlanner(remote: remote, maxEntries: 100, maxDepth: 0).plan(.local(folder)); XCTFail("Depth bound") } catch { }
        try FileManager.default.createSymbolicLink(at: deep.appendingPathComponent("link"), withDestinationURL: file)
        let result = await run(.local(folder), to: remote.root, remote: remote, journal: f.url.appendingPathComponent("journal")); XCTAssertEqual(result.state, .failed)
        let writes = await remote.mutations; XCTAssertEqual(writes, 0)
        let package = try f.directory("Example.app")
        do { _ = try await TransferTreePlanner(remote: remote).plan(.local(package)); XCTFail("Packages unsupported") } catch { }
    }
    func testMutationAndCancellationDoNotPublishPartialRoots() async throws {
        for cancel in [false, true] {
            let f = try FixtureDirectory(); let source = try f.directory("tree"); let file = try f.file("tree/file", content: String(repeating: "x", count: 200000)); let token = OperationCancellation(); let remote = TreeMemoryRemote()
            await remote.configure(token: cancel ? token : nil, mutate: cancel ? nil : file)
            let journal = f.url.appendingPathComponent("journal"); let result = await run(.local(source), to: remote.root, remote: remote, journal: journal, token: token)
            XCTAssertEqual(result.outcomes.first?.state, .partial, result.outcomes.first?.detail ?? "")
            let final = try await remote.metadata(remote.root.appending("tree")); XCTAssertNil(final)
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path)); XCTAssertFalse(try OperationJournal(directory: journal).recoverableJobs().isEmpty)
        }
    }
    func testRenameRaceKeepsExistingTreeAndLostReplyDoesNotRetry() async throws {
        for lost in [false, true] {
            let f = try FixtureDirectory(); let source = try f.directory("tree"); _ = try f.file("tree/file", content: "source"); let remote = TreeMemoryRemote(); await remote.configure(loseRename: lost, raceRename: !lost)
            let result = await run(.local(source), to: remote.root, remote: remote, journal: f.url.appendingPathComponent("journal"), decision: .keepBoth)
            XCTAssertEqual(result.outcomes.first?.state, lost ? .partial : .completed, result.outcomes.first?.detail ?? "")
            if !lost { let existing = await remote.data(try remote.root.appending("tree").appending("existing.txt")); XCTAssertEqual(existing, Data("keep".utf8)) }
        }
    }
    func testStagedFileMutationBeforeRootRenameCannotBeAccepted() async throws {
        let f = try FixtureDirectory(); let source = try f.directory("tree"); _ = try f.file("tree/file", content: "original")
        let remote = TreeMemoryRemote(); await remote.configure(tamperStage: true)
        let result = await run(.local(source), to: remote.root, remote: remote, journal: f.url.appendingPathComponent("journal"))
        XCTAssertEqual(result.outcomes.first?.state, .partial)
        let final = try await remote.metadata(remote.root.appending("tree")); XCTAssertNil(final)
    }
    func testDisconnectedDownloadCleansOwnedLocalTreeAndRetainsSource() async throws {
        let f = try FixtureDirectory(); let dest = try f.directory("downloads"); let remote = TreeMemoryRemote(); let source = try remote.root.appending("tree"); let file = try source.appending("large")
        await remote.seed(source, kind: .directory); await remote.seed(file, bytes: Data(repeating: 120, count: 200000)); await remote.configure(failReads: true)
        let result = await run(source, to: .local(dest), remote: remote, journal: f.url.appendingPathComponent("journal"))
        XCTAssertEqual(result.state, .failed); XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dest.path).isEmpty)
        let retained = await remote.data(file); XCTAssertEqual(retained?.count, 200000)
    }
    func testAggregateProgressCountsBytesAndFilesAcrossNestedDirectories() async throws {
        let f = try FixtureDirectory(); let source = try f.directory("tree"); _ = try f.directory("tree/nested")
        _ = try f.file("tree/one", content: String(repeating: "x", count: 150000)); _ = try f.file("tree/nested/two", content: String(repeating: "y", count: 70000))
        let remote = TreeMemoryRemote(); let samples = TreeProgressSamples()
        let result = await RemoteTransferExecutor(remote: remote, journal: .init(directory: f.url.appendingPathComponent("journal"))).executeRequest(.init(kind: .copy, sources: [.local(source)], destinationDirectory: remote.root), cancellation: .init(), resolveConflict: { _ in .init(.skip) }, emit: { event in if case .progress(let value) = event { samples.set(value) } })
        XCTAssertEqual(result.state, .completed); XCTAssertEqual(samples.value.bytesCopied, 220000); XCTAssertEqual(samples.value.completedItems, 2); XCTAssertEqual(result.outcomes.count, 1)
    }
    func testLocalUnicodeAliasesFailBeforeCreatingDestination() async throws {
        let f = try FixtureDirectory(); let dest = try f.directory("downloads"); let remote = TreeMemoryRemote(); let tree = try remote.root.appending("tree")
        await remote.seed(tree, kind: .directory); await remote.seed(try tree.appending("é.txt"), bytes: Data("one".utf8)); await remote.seed(try tree.appending("e\u{301}.txt"), bytes: Data("two".utf8))
        let result = await run(tree, to: .local(dest), remote: remote, journal: f.url.appendingPathComponent("journal")); XCTAssertEqual(result.state, .failed)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dest.path).isEmpty)
    }
}

private final class TreeProgressSamples: @unchecked Sendable {
    private let lock = NSLock(); private var current = CopyProgress()
    var value: CopyProgress { lock.withLock { current } }
    func set(_ value: CopyProgress) { lock.withLock { current = value } }
}
