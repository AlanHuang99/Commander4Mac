import XCTest
import CommanderCore

@MainActor final class CommandRoutingTests: XCTestCase {
    func testTransferIntentIsCapturedFromActiveWindowAndVisibleSelectionOrder() async throws {
        let f = try FixtureDirectory(); let source = try f.directory("source"); let destination = try f.directory("dest")
        let z = source.appendingPathComponent("z.txt"); let a = source.appendingPathComponent("a.txt")
        try Data().write(to: z); try Data().write(to: a)
        let workspace = WorkspaceSession(left: .local(source), right: .local(destination))
        let snapshot = try await LocalFileSystem().list(.local(source), options: .init())
        let tab = workspace.activeTab; _ = tab.apply(snapshot, for: tab.requestNavigation(to: .local(source)))
        tab.selection = [EntryID(z), EntryID(a)]
        let request = try XCTUnwrap(CommandRouter.transfer(.move, in: workspace, textEditing: false))
        let preview = CommandRouter.previewItems(in: workspace)
        workspace.activePane = .right
        _ = workspace.open(.local(f.url))
        XCTAssertEqual(request.destinationDirectory, .local(destination))
        XCTAssertEqual(request.sources, [.local(a), .local(z)])
        XCTAssertEqual(preview, [.local(a), .local(z)])
        XCTAssertNil(CommandRouter.transfer(.copy, in: workspace, textEditing: true))
        let otherWindow = WorkspaceSession()
        XCTAssertTrue(CommandRouter.previewItems(in: otherWindow).isEmpty)
    }
    func testPackagesOpenNormallyAndBrowseOnlyOnExplicitRequest() {
        let location = FileLocation.local(URL(fileURLWithPath: "/fixture/Example.app"))
        XCTAssertEqual(CommandRouter.openDisposition(kind: .package), .systemApplication)
        XCTAssertEqual(CommandRouter.openDisposition(kind: .directory), .browse)
        XCTAssertEqual(CommandRouter.packageContents(location), location)
    }
}
