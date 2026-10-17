// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import XCTest
import CommanderCore

final class LocalFileActionsTests: XCTestCase, @unchecked Sendable {
    func testRenameRejectsInvalidNamesAndCollisions() async throws {
        let f = try FixtureDirectory(); let source = try f.file("original"); _ = try f.file("occupied")
        let actions = LocalFileActions()
        for name in ["", ".", "..", "a/b", "a\0b", "occupied"] {
            do { _ = try await actions.rename(.local(source), to: name); XCTFail("Accepted invalid or occupied name") } catch { }
        }
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "fixture")
    }
    func testCaseOnlyRenameAndUndoPreserveTheFile() async throws {
        let f = try FixtureDirectory(); let source = try f.file("readme.txt")
        let actions = LocalFileActions(); let mutation = try await actions.rename(.local(source), to: "README.txt")
        XCTAssertEqual(try String(contentsOf: mutation.after.url, encoding: .utf8), "fixture")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.url.path).contains("README.txt"))
        try await actions.undo(mutation)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.url.path).contains("readme.txt"))
    }
    func testUndoRefusesReplacedRenamedItem() async throws {
        let f = try FixtureDirectory(); let source = try f.file("before")
        let actions = LocalFileActions(); let mutation = try await actions.rename(.local(source), to: "after")
        try FileManager.default.moveItem(at: mutation.after.url, to: f.url.appendingPathComponent("preserved"))
        try Data("replacement".utf8).write(to: mutation.after.url)
        do { try await actions.undo(mutation); XCTFail("Replaced item must not be renamed") } catch { }
        XCTAssertEqual(try String(contentsOf: mutation.after.url, encoding: .utf8), "replacement")
    }
    func testNewFolderUndoOnlyRemovesTheSameEmptyFolder() async throws {
        let f = try FixtureDirectory(); let actions = LocalFileActions()
        let empty = try await actions.createDirectory(named: "empty", in: .local(f.url))
        try await actions.undo(empty); XCTAssertFalse(FileManager.default.fileExists(atPath: empty.after.url.path))
        let populated = try await actions.createDirectory(named: "populated", in: .local(f.url))
        try Data("keep".utf8).write(to: populated.after.url.appendingPathComponent("child"))
        do { try await actions.undo(populated); XCTFail("Must keep nonempty folder") } catch { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: populated.after.url.appendingPathComponent("child").path))
    }
    func testTrashFailureRetainsSourceWithoutDeleteFallback() async throws {
        let f = try FixtureDirectory(); let source = try f.file("keep")
        let actions = LocalFileActions(trasher: RefusingTrasher())
        let result = await actions.trash([.local(source)])
        XCTAssertEqual(result.first?.state, .failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
}
private struct RefusingTrasher: FileTrashing {
    func trash(_ url: URL) throws -> URL? { throw CocoaError(.fileWriteNoPermission) }
}
