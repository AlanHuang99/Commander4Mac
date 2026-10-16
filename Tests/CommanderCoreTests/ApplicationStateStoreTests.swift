import XCTest
import CommanderCore

@MainActor
final class ApplicationStateStoreTests: XCTestCase {
    func testWorkspaceRoundTripKeepsPinsLocationsAndOptions() throws {
        let fixture = try FixtureDirectory()
        let sub = try fixture.directory("sub")
        let workspace = WorkspaceSession(left: .local(fixture.url), right: .local(sub))
        workspace.left.activeTab.pin = .navigable(home: .local(fixture.url))
        workspace.left.activeTab.options.textSize = 17
        workspace.splitRatio = 0.62
        _ = workspace.open(.local(sub), destination: .left, inNewTab: true)
        let store = ApplicationStateStore(directory: try fixture.directory("state"))
        try store.save(.init(windows: [try WorkspaceSnapshot(workspace)], favorites: [], shelf: []))
        let loaded = store.loadRecovering()
        XCTAssertNil(loaded.diagnostic)
        let restored = try XCTUnwrap(loaded.state.windows.first).restore()
        XCTAssertEqual(restored.left.tabs.count, 2)
        XCTAssertEqual(restored.splitRatio, 0.62, accuracy: 0.001)
        XCTAssertEqual(restored.left.tabs[0].pin, .navigable(home: .local(fixture.url)))
        XCTAssertEqual(restored.left.tabs[0].options.textSize, 17)
        XCTAssertEqual(restored.right.activeTab.location, .local(sub))
    }
    func testUnavailableTabCanBeSavedAndRestoredWithoutRetargeting() throws {
        let fixture = try FixtureDirectory()
        let missing = FileLocation.local(fixture.url.appendingPathComponent("missing"))
        let workspace = WorkspaceSession(left: missing, right: .local(fixture.url))
        let snapshot = try WorkspaceSnapshot(workspace)
        let restored = snapshot.restore()
        XCTAssertEqual(restored.left.activeTab.location.url.path, missing.url.path)
        XCTAssertNotNil(restored.left.activeTab.unresolvedReference)
    }
    func testCorruptStateIsPreservedAndReported() throws {
        let fixture = try FixtureDirectory()
        let store = ApplicationStateStore(directory: fixture.url)
        try Data("broken json".utf8).write(to: store.fileURL)
        let result = store.loadRecovering()
        XCTAssertNotNil(result.diagnostic)
        XCTAssertTrue(result.state.windows.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.url.path).contains { $0.hasPrefix("session-corrupt-") })
    }
    func testReplacedFavoriteDoesNotSilentlyResolveToNewItem() throws {
        let fixture = try FixtureDirectory()
        let original = try fixture.directory("favorite")
        let resolver = LocationResolver()
        let reference = try resolver.reference(for: .local(original))
        try FileManager.default.moveItem(at: original, to: fixture.url.appendingPathComponent("retired"))
        _ = try fixture.directory("favorite")
        switch resolver.resolve(reference) {
        case .available(let location): XCTAssertEqual(location.url.lastPathComponent, "retired")
        case .unavailable, .needsRelink: break
        }
    }
}
