// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import XCTest
import CommanderCore
import Darwin

final class ListingBudgetTests: XCTestCase, @unchecked Sendable {
    func testBoundedLocalListingPreservesFinderHiddenFlagBehavior() async throws {
        let f = try FixtureDirectory(); let file = try f.file("hidden-by-flag.txt")
        XCTAssertEqual(chflags(file.path, UInt32(UF_HIDDEN)), 0)
        let normal = try await LocalFileSystem().list(.local(f.url), options: .init(), limit: 0)
        XCTAssertFalse(normal.entries.contains { $0.name == file.lastPathComponent })
        let all = try await LocalFileSystem().list(.local(f.url), options: .init(includeHidden: true))
        XCTAssertTrue(all.entries.contains { $0.name == file.lastPathComponent })
    }
    @MainActor func testActualLocalEnumerationHonorsBudgetAndCancellation() async throws {
        let f = try FixtureDirectory(); for n in 0..<40 { _ = try f.file("file-\(n)") }
        do { _ = try await LocalFileSystem().list(.local(f.url), options: .init(includeHidden: true), limit: 3); XCTFail("Listing must stop at budget") }
        catch { XCTAssertTrue(error.localizedDescription.contains("limit")) }
        let task = Task { try Task.checkCancellation(); return try await LocalFileSystem().list(.local(f.url), options: .init(), limit: 100) }
        task.cancel(); do { _ = try await task.value; XCTFail("Canceled enumeration cannot finish") } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testTreePlannerPassesRemainingBudgetAndCancelsEnumeration() async throws {
        let remote = BudgetRemote(); let task = Task { try await TransferTreePlanner(remote: remote, maxEntries: 5).plan(remote.root) }
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await remote.started) && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let limit = await remote.limit; XCTAssertEqual(limit, 4)
        task.cancel(); do { _ = try await task.value; XCTFail("Cancellation must stop enumeration") } catch { XCTAssertTrue(error is CancellationError) }
        let unbounded = await remote.unboundedCalls; XCTAssertEqual(unbounded, 0)
    }
}
private actor BudgetRemote: RemoteFileAccess {
    nonisolated let root = FileLocation.sftp(profileID: UUID(), path: try! RemotePath("/"))
    var started = false; var limit: Int?; var unboundedCalls = 0
    func list(_ location: FileLocation, options: ListingOptions) async throws -> DirectorySnapshot { unboundedCalls += 1; throw FileOperationError.message("unbounded listing must not be requested") }
    func list(_ location: FileLocation, options: ListingOptions, limit: Int) async throws -> DirectorySnapshot { self.limit = limit; started = true; try await Task.sleep(for: .seconds(10)); throw CancellationError() }
    func metadata(_ location: FileLocation) async throws -> RemoteFileMetadata? { .init(size: nil, permissions: UInt32(S_IFDIR), modified: .distantPast) }
    func openFile(_ location: FileLocation, writeExclusive: Bool) async throws -> any RemoteFileChannel { throw CancellationError() }
    func rename(_ source: FileLocation, to destination: FileLocation) async throws { throw CancellationError() }
    func createDirectory(_ location: FileLocation) async throws { throw CancellationError() }
}
