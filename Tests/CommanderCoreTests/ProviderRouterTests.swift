import XCTest
import CommanderCore

@MainActor final class ProviderRouterTests: XCTestCase {
    func testProviderDispatchAndStaleRemoteReplies() async throws {
        let remoteID = UUID()
        let remote = FileLocation.sftp(profileID: remoteID, path: try RemotePath("/slow"))
        let local = FileLocation.local(URL(fileURLWithPath: "/tmp/local"))
        let router = ProviderRouter(local: LabelProvider(label: "local"), remote: LabelProvider(label: "remote"))
        let remoteResult = try await router.list(remote, options: .init())
        XCTAssertEqual(remoteResult.entries.first?.name, "remote")
        let workspace = WorkspaceSession(left: remote, right: local)
        let loader = DirectoryLoader(workspace: workspace, provider: router)
        let old = workspace.open(remote, destination: .left)
        let pending = Task { await loader.load(target: old, options: .init()) }
        await Task.yield()
        let current = workspace.open(local, destination: .left)
        await loader.load(target: current, options: .init()); await pending.value
        XCTAssertEqual(workspace.left.activeTab.visibleEntries.first?.name, "local")
    }
    func testRemotePathNavigationRetainsProfileAndExplicitFileURLReturnsLocal() throws {
        let id = UUID(); let current = FileLocation.sftp(profileID: id, path: try RemotePath("/folder"))
        let child = try PathNavigation.resolve("child #?.txt", from: current)
        XCTAssertEqual(child.profileID, id); XCTAssertEqual(child.remotePath?.rawValue, "/folder/child #?.txt")
        XCTAssertEqual(try PathNavigation.resolve("/absolute", from: current).remotePath?.rawValue, "/absolute")
        XCTAssertTrue(try PathNavigation.resolve("file:///tmp/local", from: current).isLocal)
    }
    func testRemotePreviewsAndRestorationNeverOpenLocalOrConnect() async throws {
        let remote = FileLocation.sftp(profileID: UUID(), path: try RemotePath("/tmp"))
        let workspace = WorkspaceSession(left: remote)
        let file = FileEntry(location: try remote.appending("private.txt"), name: "private.txt", kind: .file)
        _ = workspace.activeTab.apply(.init(location: remote, entries: [file]), for: workspace.activeTab.requestNavigation(to: remote))
        workspace.activeTab.selection = [file.id]
        XCTAssertTrue(CommandRouter.previewItems(in: workspace).isEmpty)
        let restored = try WorkspaceSnapshot(workspace).restore()
        let manager = SFTPConnectionManager()
        XCTAssertEqual(restored.left.activeTab.location, remote)
        let connected = await manager.isConnected(remote.profileID!)
        XCTAssertFalse(connected)
    }
}
private struct LabelProvider: DirectoryProviding {
    let label: String
    func list(_ location: FileLocation, options: ListingOptions) async throws -> DirectorySnapshot {
        if label == "remote" { try await Task.sleep(for: .milliseconds(25)) }
        return .init(location: location, entries: [.init(location: try location.appending(label), name: label, kind: .file)])
    }
}
