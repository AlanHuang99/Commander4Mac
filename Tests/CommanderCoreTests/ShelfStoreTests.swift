import XCTest
import CommanderCore

@MainActor final class ShelfStoreTests: XCTestCase {
    func testMultiSourceDedupAndRemovalNeverDeleteOriginals() async throws {
        let f = try FixtureDirectory(); let a = try f.file("a"); let b = try f.file("b")
        let shelf = ShelfStore()
        try await shelf.stage([.local(a), .local(b), .local(a)])
        XCTAssertEqual(shelf.items.count, 2)
        shelf.remove(ids: [shelf.items[0].id])
        shelf.clear()
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
    }
    func testResultsRemoveOnlySuccessfullyTransferredCapturedItems() async throws {
        let f = try FixtureDirectory(); let a = try f.file("a"); let b = try f.file("b")
        let shelf = ShelfStore(); try await shelf.stage([.local(a), .local(b)])
        let captured = Set(shelf.items.map(\.id))
        shelf.apply(.init(jobID: UUID(), outcomes: [.init(source: .local(a), state: .completed), .init(source: .local(b), state: .partial)], state: .failed), capturedIDs: captured)
        XCTAssertEqual(shelf.items.map(\.displayName), ["b"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
        shelf.clear(); try await shelf.stage([.local(a)])
        shelf.apply(.init(jobID: UUID(), outcomes: [.init(source: .local(a), state: .completed)], state: .completed), capturedIDs: captured)
        XCTAssertEqual(shelf.items.count, 1, "Restaged entries must survive an older job's completion")
    }
    func testUnavailableStagedItemIsVisibleAndCannotSilentlyResolveReplacement() async throws {
        let f = try FixtureDirectory(); let a = try f.file("a")
        let shelf = ShelfStore(); try await shelf.stage([.local(a)])
        try FileManager.default.removeItem(at: a)
        try Data("replacement".utf8).write(to: a)
        do { _ = try await shelf.resolvedLocations(); XCTFail("Should require relinking") } catch { }
        XCTAssertEqual(shelf.items.count, 1)
    }
}
