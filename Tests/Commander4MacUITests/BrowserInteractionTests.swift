// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import XCTest

@MainActor
final class BrowserInteractionTests: XCTestCase {
    func testTwoNativePanesAndIndependentFilters() {
        let app = XCUIApplication()
        app.launchArguments = ["-accessSetupAcknowledged", "YES"]
        app.launch()
        XCTAssertTrue(app.tables["left.fileTable"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.tables["right.fileTable"].exists)
        let filter = app.textFields["left.filter"]
        filter.click()
        filter.typeText("Downloads")
        XCTAssertEqual(filter.value as? String, "Downloads")
        XCTAssertEqual(app.textFields["right.filter"].value as? String ?? "", "")
        app.terminate()
    }
}
