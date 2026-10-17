// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import XCTest
import CommanderCore

final class PreferencesStoreTests: XCTestCase {
    func testPreferencesRoundTripAndInvalidSizesClampIndependently() throws {
        let fixture = try FixtureDirectory()
        let store = PreferencesStore(directory: fixture.url)
        var value = Preferences()
        value.appearance = .dark; value.defaultDestination = .left
        value.view.textSize = 30; value.view.listIconSize = 4
        try store.save(value)
        let restored = store.load()
        XCTAssertEqual(restored.appearance, .dark)
        XCTAssertEqual(restored.defaultDestination, .left)
        XCTAssertEqual(restored.view.textSize, 20)
        XCTAssertEqual(restored.view.listIconSize, 16)
    }
    func testCorruptPreferencesFallBackToUsefulDefaults() throws {
        let fixture = try FixtureDirectory()
        let store = PreferencesStore(directory: fixture.url)
        try Data("invalid".utf8).write(to: store.fileURL)
        let preferences = store.load()
        XCTAssertEqual(preferences.appearance, .system)
        XCTAssertEqual(preferences.defaultDestination, .current)
        XCTAssertEqual(preferences.view.textSize, 13)
        XCTAssertEqual(preferences.view.listIconSize, 20)
    }
}
