// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import XCTest
import CommanderCore

@MainActor final class RemoteLocationTests: XCTestCase {
    func testRemoteUnicodeDirectoryEntriesKeepDistinctByteIdentity() throws {
        let id = UUID()
        let a = FileLocation.sftp(profileID: id, path: try RemotePath("/caf\u{00e9}"))
        let b = FileLocation.sftp(profileID: id, path: try RemotePath("/cafe\u{0301}"))
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a.remotePath, b.remotePath)
        XCTAssertNotEqual(EntryID(a.url), EntryID(b.url))
        XCTAssertEqual(Set([a,b]).count, 2)
    }
    func testRemoteIdentityAndLiteralNamesRemainProviderQualified() throws {
        let one = UUID(); let two = UUID(); let path = try RemotePath("/folder/./inner/../file #? 中文.txt")
        XCTAssertEqual(path.rawValue, "/folder/file #? 中文.txt")
        let a = FileLocation.sftp(profileID: one, path: path)
        let b = FileLocation.sftp(profileID: two, path: path)
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(EntryID(a.url), EntryID(b.url))
        XCTAssertFalse(a.url.isFileURL)
        XCTAssertEqual(a.parent.remotePath?.rawValue, "/folder")
        for name in ["..", ".", "a/b", "", "nul\0name"] { XCTAssertThrowsError(try path.appending(name)) }
        XCTAssertThrowsError(try RemotePath("relative"))
        XCTAssertThrowsError(try RemotePath("/../escape"))
    }
    func testLegacyLocalLocationAndRemoteSessionRoundTrip() throws {
        let local = FileLocation.local(URL(fileURLWithPath: "/tmp/legacy"))
        XCTAssertEqual(try JSONDecoder().decode(FileLocation.self, from: JSONEncoder().encode(local)), local)
        let remote = FileLocation.sftp(profileID: UUID(), path: try RemotePath("/remote"))
        let workspace = WorkspaceSession(left: remote)
        let restored = try WorkspaceSnapshot(workspace).restore()
        XCTAssertEqual(restored.left.activeTab.location, remote)
        XCTAssertNil(restored.left.activeTab.unresolvedReference)
    }
    func testBookmarkResolutionRejectsNonFileURLsEvenWhenLocalIdentityMatches() throws {
        let f = try FixtureDirectory()
        let remote = FileLocation.sftp(profileID: UUID(), path: try RemotePath(f.url.path))
        let reference = LocationReference(bookmark: Data(), displayURL: remote.url, expectedIdentity: try LocationResolver.identity(at: f.url))
        if case .available = LocationResolver().resolve(reference) { XCTFail("A remote URL must never resolve through a matching local path") }
        XCTAssertFalse(FileLocation.local(remote.url).isLocal)
    }
    func testLocalServicesNeverUseRemotePathsAsLocalPaths() async throws {
        let f = try FixtureDirectory()
        let remote = FileLocation.sftp(profileID: UUID(), path: try RemotePath(f.url.path))
        do { _ = try await LocalFileSystem().list(remote); XCTFail("Must reject remote provider") } catch { }
        XCTAssertThrowsError(try LocationResolver().reference(for: remote))
        XCTAssertThrowsError(try LocalTransferPlanner().plan(.init(kind: .copy, sources: [remote], destinationDirectory: .local(f.url))))
        do { _ = try await LocalFileActions().createDirectory(named: "must-not-exist", in: remote); XCTFail("Must reject remote provider") } catch { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.url.appendingPathComponent("must-not-exist").path))
    }
}
