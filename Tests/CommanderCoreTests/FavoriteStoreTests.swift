// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import XCTest
import CommanderCore

@MainActor
final class FavoriteStoreTests: XCTestCase {
    func testFavoriteDestinationReorderRenameAndRemoval() async throws {
        let fixture = try FixtureDirectory()
        let store = FavoriteStore()
        try await store.add(name: "First", location: .local(fixture.url), destination: .left)
        try await store.add(name: "Second", location: .local(fixture.url), destination: nil)
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
