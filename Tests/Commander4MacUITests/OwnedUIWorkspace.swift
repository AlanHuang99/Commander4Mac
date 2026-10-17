// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import XCTest

@MainActor final class OwnedUIWorkspace {
    let app = XCUIApplication()
    let directory: URL
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Commander4MacUITest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("Owned UI fixture".utf8).write(to: directory.appendingPathComponent("one.txt"))
        app.launchArguments = ["-accessSetupAcknowledged", "YES"]
        app.launchEnvironment["COMMANDER_TEST_STATE_DIRECTORY"] = directory.appendingPathComponent("State").path
    }
    func launch() {
        app.launch()
        for pane in ["left", "right"] {
            let path = app.textFields[pane + ".path"]
            XCTAssertTrue(path.waitForExistence(timeout: 8))
            path.click(); path.typeKey("a", modifierFlags: .command); path.typeText(directory.path + "\n")
        }
    }
    func cleanup() {
        app.terminate()
        try? FileManager.default.removeItem(at: directory)
    }
}
