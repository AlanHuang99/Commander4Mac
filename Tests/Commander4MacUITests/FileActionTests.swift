import XCTest

@MainActor final class FileActionTests: XCTestCase {
    func testFileDragCopiesIntoOtherPane() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CommanderDragUI-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"); let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        try Data("drag fixture".utf8).write(to: source.appendingPathComponent("drag.txt"))
        let app = XCUIApplication(); app.launchArguments = ["-accessSetupAcknowledged", "YES"]; app.launch()
        for (id, url) in [("left.path", source), ("right.path", destination)] {
            let path = app.textFields[id]; XCTAssertTrue(path.waitForExistence(timeout: 8))
            path.click(); path.typeKey("a", modifierFlags: .command); path.typeText(url.path); path.typeKey(.return, modifierFlags: [])
        }
        let sourceRow = app.tables["left.fileTable"].tableRows.firstMatch
        XCTAssertTrue(sourceRow.waitForExistence(timeout: 5))
        sourceRow.press(forDuration: 1, thenDragTo: app.tables["right.fileTable"])
        let copied = NSPredicate { _, _ in FileManager.default.fileExists(atPath: destination.appendingPathComponent("drag.txt").path) }
        expectation(for: copied, evaluatedWith: nil); waitForExpectations(timeout: 8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("drag.txt").path))
        app.terminate()
    }
    func testNativeInlineRename() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CommanderActionsUI-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("action fixture".utf8).write(to: root.appendingPathComponent("before.txt"))
        let app = XCUIApplication(); app.launchArguments = ["-accessSetupAcknowledged", "YES"]; app.launch()
        let path = app.textFields["left.path"]; XCTAssertTrue(path.waitForExistence(timeout: 8))
        path.click(); path.typeKey("a", modifierFlags: .command); path.typeText(root.path); path.typeKey(.return, modifierFlags: [])
        let row = app.tables["left.fileTable"].tableRows.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.click(); row.typeKey(.downArrow, modifierFlags: [])
        row.typeKey(.return, modifierFlags: []); app.typeText("after.txt"); app.typeKey(.return, modifierFlags: [])
        let renamed = NSPredicate { _, _ in FileManager.default.fileExists(atPath: root.appendingPathComponent("after.txt").path) }
        expectation(for: renamed, evaluatedWith: nil); waitForExpectations(timeout: 8)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("after.txt"), encoding: .utf8), "action fixture")
        app.terminate()
    }
}
