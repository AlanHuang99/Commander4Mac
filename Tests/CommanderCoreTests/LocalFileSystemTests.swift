import XCTest
import CommanderCore

@MainActor
final class LocalFileSystemTests: XCTestCase {
    func testListingClassifiesPackagesLinksAndHiddenFilesWithoutFollowingLinks() async throws {
        let fixture = try FixtureDirectory()
        _ = try fixture.file("report.pdf")
        _ = try fixture.file(".secret")
        _ = try fixture.directory("Folder")
        _ = try fixture.directory("Demo.app")
        try FileManager.default.createSymbolicLink(atPath: fixture.url.appendingPathComponent("broken").path, withDestinationPath: "/missing/commander-fixture")
        let snapshot = try await LocalFileSystem().list(.local(fixture.url), options: .init(includeHidden: false))
        XCTAssertEqual(Set(snapshot.entries.map(\.name)), ["report.pdf", "Folder", "Demo.app", "broken"])
        XCTAssertEqual(snapshot.entries.first { $0.name == "broken" }?.kind, .symbolicLink)
        XCTAssertEqual(snapshot.entries.first { $0.name == "Demo.app" }?.kind, .package)
        let hidden = try await LocalFileSystem().list(.local(fixture.url), options: .init(includeHidden: true))
        XCTAssertTrue(hidden.entries.contains { $0.name == ".secret" })
    }
    func testHardLinksHaveDistinctRowsButSameFilesystemIdentity() async throws {
        let fixture = try FixtureDirectory()
        let original = try fixture.file("one.txt")
        try FileManager.default.linkItem(at: original, to: fixture.url.appendingPathComponent("two.txt"))
        let rows = try await LocalFileSystem().list(.local(fixture.url), options: .init()).entries
        XCTAssertEqual(rows.count, 2)
        XCTAssertNotEqual(rows[0].id, rows[1].id)
        XCTAssertEqual(rows[0].fileIdentity, rows[1].fileIdentity)
    }
    func testUnicodeAndShellCharactersRemainLiteral() async throws {
        let fixture = try FixtureDirectory()
        let name = "资料 café $HOME `hello`.txt"
        _ = try fixture.file(name)
        let snapshot = try await LocalFileSystem().list(.local(fixture.url), options: .init())
        XCTAssertEqual(snapshot.entries.map(\.name), [name])
    }
    func testMissingDirectoryThrowsInsteadOfReturningEmptySuccess() async throws {
        let fixture = try FixtureDirectory()
        do {
            _ = try await LocalFileSystem().list(.local(fixture.url.appendingPathComponent("missing")), options: .init())
            XCTFail("Missing directory was reported as a valid empty folder")
        } catch let failure as FileFailure {
            XCTAssertEqual(failure.category, .notFound)
        }
    }
    func testPermissionErrorsRemainDistinguishableFromMissingFiles() {
        let failure = FileFailure(NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)), at: .local(URL(fileURLWithPath: "/denied")))
        XCTAssertEqual(failure.category, .accessDenied)
    }
}
