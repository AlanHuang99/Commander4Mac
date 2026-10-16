import XCTest

@MainActor final class ConnectionUITests: XCTestCase {
    func testConnectEditorIsDiscoverableAndCredentialsAreSecureFields() {
        let app = XCUIApplication(); app.launchArguments = ["-accessSetupAcknowledged", "YES"]; app.launch()
        let connect = app.buttons["connections.open"]
        XCTAssertTrue(connect.waitForExistence(timeout: 8)); connect.click()
        XCTAssertTrue(app.textFields["connection.host"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["connection.secret"].exists)
        app.buttons["connection.cancel"].click()
        XCTAssertTrue(app.tables["left.fileTable"].exists)
        app.terminate()
    }
}
