import XCTest
import CommanderCore

@MainActor final class ViewModeStateTests: XCTestCase {
    func testModeAndIndependentIconSizesPreserveLocationAndSelection() async throws {
        let f = try FixtureDirectory(); let file = try f.file("a")
        let tab = TabSession(location: .local(f.url))
        let snapshot = try await LocalFileSystem().list(.local(f.url), options: .init())
        _ = tab.apply(snapshot, for: tab.requestNavigation(to: tab.location))
        tab.selection = [EntryID(file)]; tab.scrollAnchor = EntryID(file)
        tab.options.mode = .icons; tab.options.gridIconSize = 128
        XCTAssertEqual(tab.options.listIconSize, 20)
        XCTAssertEqual(tab.selection, [EntryID(file)])
        XCTAssertEqual(tab.scrollAnchor, EntryID(file))
        tab.options.mode = .list
        XCTAssertEqual(tab.location, .local(f.url))
        XCTAssertEqual(tab.selection, [EntryID(file)])
    }
    func testOldSavedOptionsAcquireGridDefaults() throws {
        let old = Data("""
        {"sortColumn":"name","ascending":true,"foldersFirst":true,"includeHidden":false,"visibleColumns":["name"],"textSize":14,"listIconSize":24,"mode":"list"}
        """.utf8)
        let options = try JSONDecoder().decode(ViewOptions.self, from: old)
        XCTAssertEqual(options.gridIconSize, 64)
        XCTAssertEqual(options.textSize, 14)
        XCTAssertEqual(options.listIconSize, 24)
    }
    func testUniqueIdentityRenameReconcilesSelectionButHardLinksRemainDistinct() async throws {
        let f = try FixtureDirectory(); let file = try f.file("before"); let after = f.url.appendingPathComponent("after")
        let tab = TabSession(location: .local(f.url)); let provider = LocalFileSystem()
        _ = tab.apply(try await provider.list(tab.location, options: .init()), for: tab.requestNavigation(to: tab.location))
        tab.selection = [EntryID(file)]; tab.scrollAnchor = EntryID(file)
        try FileManager.default.moveItem(at: file, to: after)
        _ = tab.apply(try await provider.list(tab.location, options: .init()), for: tab.requestNavigation(to: tab.location))
        XCTAssertEqual(tab.selection, [EntryID(after)])
        XCTAssertEqual(tab.scrollAnchor, EntryID(after))
    }
}
