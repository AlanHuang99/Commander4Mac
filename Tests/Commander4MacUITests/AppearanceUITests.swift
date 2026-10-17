// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import XCTest

@MainActor final class AppearanceUITests: XCTestCase {
    func testAppearanceChangesReachBothPanesAndNewTabs() throws {
        let fixture = try OwnedUIWorkspace(); defer { fixture.cleanup() }
        fixture.launch(); let app = fixture.app
        let left = app.buttons["left.viewOptions"]
        XCTAssertTrue(left.waitForExistence(timeout: 5)); left.click()
        app.sliders["left.appearance.textSize"].adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertEqual(app.sliders["left.appearance.textSize"].value as? String, "19 points")
        app.buttons["left.appearance.done"].click()
        app.buttons["right.viewOptions"].click()
        XCTAssertEqual(app.sliders["right.appearance.textSize"].value as? String, "19 points")
        app.buttons["right.appearance.done"].click()
        app.textFields["right.path"].click()
        app.typeKey("t", modifierFlags: .command)
        app.buttons["right.viewOptions"].click()
        XCTAssertEqual(app.sliders["right.appearance.textSize"].value as? String, "19 points")
    }

    func testOptOutPersistsAnIndividualTabsStyleAcrossRelaunch() throws {
        let fixture = try OwnedUIWorkspace(); defer { fixture.cleanup() }
        fixture.launch(); let app = fixture.app
        let left = app.buttons["left.viewOptions"]
        XCTAssertTrue(left.waitForExistence(timeout: 5)); left.click()
        app.checkBoxes["left.appearance.share"].click()
        app.sliders["left.appearance.textSize"].adjust(toNormalizedSliderPosition: 0.5)
        app.buttons["left.appearance.done"].click()
        app.buttons["right.viewOptions"].click()
        XCTAssertEqual(app.sliders["right.appearance.textSize"].value as? String, "13 points")
        app.buttons["right.appearance.done"].click()
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 8))
        fixture.launch()
        app.buttons["left.viewOptions"].click()
        XCTAssertEqual(app.sliders["left.appearance.textSize"].value as? String, "19 points")
    }
}
