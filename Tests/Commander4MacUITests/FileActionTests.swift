import XCTest

@MainActor final class FileActionTests: XCTestCase {
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
