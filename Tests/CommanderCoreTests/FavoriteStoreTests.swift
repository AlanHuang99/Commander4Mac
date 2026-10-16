import XCTest
import CommanderCore

@MainActor
final class FavoriteStoreTests: XCTestCase {
    func testFavoriteDestinationReorderRenameAndRemoval() throws {
        let fixture = try FixtureDirectory()
        let store = FavoriteStore()
        try store.add(name: "First", location: .local(fixture.url), destination: .left)
        try store.add(name: "Second", location: .local(fixture.url), destination: nil)
        let id = store.items[1].id
        store.rename(id: id, to: "Renamed")
        store.move(id: id, to: 0)
        XCTAssertEqual(store.items.map(\.name), ["Renamed", "First"])
        XCTAssertEqual(store.items[1].destination, .left)
        store.remove(id: id)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.url.path))
    }
}
