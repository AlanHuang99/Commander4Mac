// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import XCTest

@MainActor final class ConnectionUITests: XCTestCase {
    func testSavedConnectionCanBeReopenedWithoutLosingCustomEndpoint() throws {
        let fixture = try OwnedUIWorkspace(); defer { fixture.cleanup() }
        fixture.launch(); let app = fixture.app
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(app.popUpButtons["connection.saved"].waitForExistence(timeout: 5))
        app.popUpButtons["connection.protocol"].click(); app.menuItems["SMB"].click()
        for (field, value) in [("name", "Owned UI Server"), ("host", "files.example.test"), ("port", "1445"), ("share", "Design"), ("username", "artist"), ("path", "/Projects")] {
            let input = app.textFields["connection." + field]
            input.click(); input.typeKey("a", modifierFlags: .command); input.typeText(value)
        }
        app.buttons["connection.save"].click()
        XCTAssertTrue(app.buttons["connections.open"].waitForExistence(timeout: 5))
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 8)); fixture.launch()
        app.typeKey("k", modifierFlags: .command)
        app.popUpButtons["connection.saved"].click()
        app.menuItems.matching(NSPredicate(format: "label CONTAINS %@", "Owned UI Server")).firstMatch.click()
        XCTAssertEqual(app.textFields["connection.port"].value as? String, "1445")
        XCTAssertEqual(app.textFields["connection.share"].value as? String, "Design")
        XCTAssertEqual(app.textFields["connection.path"].value as? String, "/Projects")
        XCTAssertEqual(app.secureTextFields["connection.secret"].value as? String, "")
        app.buttons["connection.remove"].click()
        XCTAssertEqual(app.textFields["connection.host"].value as? String, "")
        app.buttons["connection.cancel"].click()
    }

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
