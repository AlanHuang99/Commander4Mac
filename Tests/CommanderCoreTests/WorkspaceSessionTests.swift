import XCTest
import CommanderCore

@MainActor
final class WorkspaceSessionTests: XCTestCase {
    func testLockedHistoryBackOpensOrdinaryTabAndPreservesLockedHistory() {
        let workspace = WorkspaceSession(left: home, right: other)
        _ = workspace.open(other, destination: .left)
        let locked = workspace.left.activeTab
        locked.pin = .locked(home: other)
        workspace.activePane = .right
        let target = workspace.navigateHistory(in: .left, forward: false)
        XCTAssertEqual(locked.location, other)
        XCTAssertEqual(locked.historyIndex, 1)
        XCTAssertEqual(workspace.left.tabs.count, 2)
        XCTAssertEqual(workspace.left.activeTab.location, home)
        XCTAssertFalse(workspace.left.activeTab.pin.isPinned)
        XCTAssertEqual(target?.tabID, workspace.left.activeTab.id)
        XCTAssertEqual(workspace.activePane, .left)
        XCTAssertEqual(workspace.right.tabs.count, 1)
        XCTAssertEqual(workspace.right.activeTab.location, other)
        XCTAssertNotNil(workspace.navigateHistory(in: .left, forward: true))
        XCTAssertEqual(workspace.left.activeTab.location, other)
    }
    func testLockedHistoryForwardOpensOrdinaryTabAndPreservesLockedHistory() {
        let workspace = WorkspaceSession(left: home, right: other)
        _ = workspace.open(other, destination: .left)
        _ = workspace.navigateHistory(in: .left, forward: false)
        let locked = workspace.left.activeTab
        locked.pin = .locked(home: home)
        let target = workspace.navigateHistory(in: .left, forward: true)
        XCTAssertEqual(locked.location, home)
        XCTAssertEqual(locked.historyIndex, 0)
        XCTAssertEqual(workspace.left.tabs.count, 2)
        XCTAssertEqual(workspace.left.activeTab.location, other)
        XCTAssertEqual(target?.ticket.location, other)
    }
    let home = FileLocation.local(URL(fileURLWithPath: "/tmp/home"))
    let other = FileLocation.local(URL(fileURLWithPath: "/tmp/other"))
    func testLockedPinOpensNavigationInNewTabWithoutChangingHome() {
        let workspace = WorkspaceSession(left: home, right: other)
        let tab = workspace.left.activeTab
        tab.pin = .locked(home: home)
        let target = workspace.open(other, destination: .left, inNewTab: false)
        XCTAssertEqual(workspace.left.tabs.count, 2)
        XCTAssertEqual(tab.location, home)
        XCTAssertNotEqual(target.tabID, tab.id)
    }
    func testNavigablePinKeepsItsCurrentLocationAcrossTabSwitch() {
        let workspace = WorkspaceSession(left: home, right: other)
        let pinned = workspace.left.activeTab
        pinned.pin = .navigable(home: home)
        _ = workspace.open(other, destination: .left, inNewTab: false)
        _ = workspace.open(home, destination: .left, inNewTab: true)
        workspace.left.activeTabID = pinned.id
        XCTAssertEqual(pinned.location, other)
        _ = workspace.returnToPinnedFolder(in: .left, tabID: pinned.id)
        XCTAssertEqual(pinned.location, home)
    }
    func testRoutingToLeftDoesNotChangeRightPaneAndActivatesLeft() {
        let workspace = WorkspaceSession(left: home, right: other)
        workspace.activePane = .right
        _ = workspace.open(other, destination: .left, inNewTab: false)
        XCTAssertEqual(workspace.activePane, .left)
        XCTAssertEqual(workspace.right.activeTab.location, other)
        XCTAssertEqual(workspace.right.tabs.count, 1)
    }
    func testOldDirectoryReplyCannotReplaceNewLocation() {
        let tab = TabSession(location: home)
        let old = tab.requestNavigation(to: home)
        let new = tab.requestNavigation(to: other)
        XCTAssertFalse(tab.apply(.init(location: home, entries: []), for: old))
        XCTAssertTrue(tab.apply(.init(location: other, entries: []), for: new))
        XCTAssertEqual(tab.location, other)
    }
    func testHistoryIsIndependentAndNavigatingBackDoesNotAddHistory() {
        let workspace = WorkspaceSession(left: home, right: other)
        _ = workspace.open(other, destination: .left, inNewTab: false)
        XCTAssertNotNil(workspace.left.activeTab.goBack())
        XCTAssertEqual(workspace.left.activeTab.location, home)
        XCTAssertNotNil(workspace.left.activeTab.goForward())
        XCTAssertNil(workspace.right.activeTab.goBack())
    }
    func testWindowFocusIsNotShared() {
        let one = WorkspaceSession(left: home, right: other)
        let two = WorkspaceSession(left: home, right: other)
        one.activePane = .right
        XCTAssertEqual(two.activePane, .left)
    }
}
