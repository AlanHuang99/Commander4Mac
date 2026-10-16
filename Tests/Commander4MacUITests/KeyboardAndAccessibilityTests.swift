import XCTest

@MainActor final class KeyboardAndAccessibilityTests: XCTestCase {
    func testPathFilterAndTabsRemainWindowLocal() {
        let app = XCUIApplication(); app.launchArguments = ["-accessSetupAcknowledged", "YES"]; app.launch()
        XCTAssertTrue(app.tables["left.fileTable"].waitForExistence(timeout: 8))
        app.typeKey("l", modifierFlags: .command)
        XCTAssertTrue(app.textFields["left.path"].exists)
        app.typeKey("f", modifierFlags: .command); app.typeText("keyboard fixture")
        XCTAssertEqual(app.textFields["left.filter"].value as? String, "keyboard fixture")
        XCTAssertEqual(app.textFields["right.filter"].value as? String ?? "", "")
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(app.tables["left.fileTable"].exists)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.tables["left.fileTable"].exists)
        app.terminate()
    }
}
