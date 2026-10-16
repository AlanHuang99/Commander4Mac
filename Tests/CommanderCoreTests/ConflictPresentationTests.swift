import XCTest
import CommanderCore

@MainActor final class ConflictPresentationTests: XCTestCase {
    func testConflictWithNoWindowsIsPresentedWhenWindowReopens() {
        let router = ConflictPresentationRouter()
        let owner = UUID(); let reopened = UUID()
        router.register(owner)
        router.unregister(owner)
        router.setPending(owner: owner)
        XCTAssertNil(router.presenter)
        router.register(reopened)
        XCTAssertEqual(router.presenter, reopened)
        router.unregister(reopened)
        XCTAssertNil(router.presenter)
        router.register(owner)
        XCTAssertEqual(router.presenter, owner)
        router.clearPending()
        XCTAssertNil(router.presenter)
    }
    func testPendingConflictPrefersOwnerAndFallsBackWithoutQueueMutation() {
        let router = ConflictPresentationRouter()
        let owner = UUID(); let fallback = UUID()
        router.register(fallback); router.setPending(owner: owner)
        XCTAssertEqual(router.presenter, fallback)
        router.register(owner)
        XCTAssertEqual(router.presenter, owner)
        router.unregister(owner)
        XCTAssertEqual(router.presenter, fallback)
    }
}
