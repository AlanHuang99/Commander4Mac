// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import XCTest
import CommanderCore

private struct DelayedProvider: DirectoryProviding {
    func list(_ location: FileLocation, options: ListingOptions) async throws -> DirectorySnapshot {
        if location.title == "slow" { try await Task.sleep(for: .milliseconds(30)) }
        return .init(location: location, entries: [.init(location: .local(location.url.appendingPathComponent("item")), name: location.title, kind: .file)])
    }
}
@MainActor
final class DirectoryLoaderTests: XCTestCase {
    func testDelayedResponseCannotReplaceNewestDirectory() async {
        let slow = FileLocation.local(URL(fileURLWithPath: "/tmp/slow"))
        let fast = FileLocation.local(URL(fileURLWithPath: "/tmp/fast"))
        let workspace = WorkspaceSession(left: slow, right: fast)
        let loader = DirectoryLoader(workspace: workspace, provider: DelayedProvider())
        let old = workspace.open(slow, destination: .left)
        let first = Task { await loader.load(target: old, options: .init()) }
        await Task.yield()
        let latest = workspace.open(fast, destination: .left)
        await loader.load(target: latest, options: .init())
        await first.value
        XCTAssertEqual(workspace.left.activeTab.visibleEntries.map(\.name), ["fast"])
    }
    func testFilterAndSortingPreserveDistinctRows() {
        let location = FileLocation.local(URL(fileURLWithPath: "/tmp/fixture"))
        let tab = TabSession(location: location)
        let ticket = tab.requestNavigation(to: location)
        _ = tab.apply(.init(location: location, entries: [
            .init(location: .local(location.url.appendingPathComponent("file10")), name: "file10", kind: .file),
            .init(location: .local(location.url.appendingPathComponent("file2")), name: "file2", kind: .file),
            .init(location: .local(location.url.appendingPathComponent("Zoo")), name: "Zoo", kind: .directory)
        ]), for: ticket)
        XCTAssertEqual(tab.visibleEntries.map(\.name), ["Zoo", "file2", "file10"])
        tab.filter = "FILE"
        XCTAssertEqual(tab.visibleEntries.map(\.name), ["file2", "file10"])
    }
}
