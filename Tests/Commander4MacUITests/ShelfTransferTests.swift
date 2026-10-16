import XCTest

@MainActor final class ShelfTransferTests: XCTestCase {
    func testShelfStagesWithoutMovingAndCopiesToCapturedRightFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CommanderShelfUI-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"); let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        try Data("shelf fixture".utf8).write(to: source.appendingPathComponent("sample.txt"))
        let app = XCUIApplication(); app.launchArguments = ["-accessSetupAcknowledged", "YES"]; app.launch()
        for (id, url) in [("left.path", source), ("right.path", destination)] {
            let field = app.textFields[id]; XCTAssertTrue(field.waitForExistence(timeout: 8))
            field.click(); field.typeKey("a", modifierFlags: .command); field.typeText(url.path); field.typeKey(.return, modifierFlags: [])
        }
        let row = app.tables["left.fileTable"].tableRows.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.click()
        app.buttons["Add Selection"].click()
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("sample.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("sample.txt").path))
        app.buttons.matching(identifier: "Copy to Right").element(boundBy: 1).click()
        let copied = NSPredicate { _, _ in FileManager.default.fileExists(atPath: destination.appendingPathComponent("sample.txt").path) }
        expectation(for: copied, evaluatedWith: nil); waitForExpectations(timeout: 8)
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("sample.txt"), encoding: .utf8), "shelf fixture")
        app.terminate()
    }
}
