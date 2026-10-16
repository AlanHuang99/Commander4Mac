import XCTest

@MainActor final class KeyboardAndAccessibilityTests: XCTestCase {
    func testConnectShortcutSurvivesSheetsSettingsAndNewWindows() {
        let app = XCUIApplication(); app.launchArguments = ["-accessSetupAcknowledged", "YES"]; app.launch()
        XCTAssertTrue(app.tables["left.fileTable"].waitForExistence(timeout: 8))
        for _ in 0..<3 {
            app.typeKey("k", modifierFlags: .command)
            XCTAssertTrue(app.buttons["connection.cancel"].waitForExistence(timeout: 3))
            app.buttons["connection.cancel"].click()
        }
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows["com_apple_SwiftUI_Settings_window"]; XCTAssertTrue(settings.waitForExistence(timeout: 3))
        app.typeKey("w", modifierFlags: .command); XCTAssertTrue(settings.waitForNonExistence(timeout: 3))
        app.typeKey("n", modifierFlags: .command)
        app.textFields["right.path"].firstMatch.click()
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(app.buttons["connection.cancel"].waitForExistence(timeout: 3))
        app.buttons["connection.cancel"].click(); app.terminate()
    }
    func testCommandWClosesTabBeforeWindow() {
        let app = XCUIApplication(); app.launchArguments = ["-accessSetupAcknowledged", "YES"]; app.launch()
        XCTAssertTrue(app.tables["left.fileTable"].waitForExistence(timeout: 8))
        let windowID = app.windows.firstMatch.identifier
        app.typeKey("t", modifierFlags: .command)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.windows[windowID].exists, "Closing one of two tabs must preserve its window")
        app.terminate()
    }
    func testClosingSettingsDoesNotRouteToTheFileWindow() {
        let app = XCUIApplication(); app.launchArguments = ["-accessSetupAcknowledged", "YES"]; app.launch()
        XCTAssertTrue(app.tables["left.fileTable"].waitForExistence(timeout: 8))
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.tables["left.fileTable"].exists)
        app.terminate()
    }
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
