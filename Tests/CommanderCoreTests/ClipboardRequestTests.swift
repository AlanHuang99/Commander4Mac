import XCTest
import CommanderCore

final class ClipboardRequestTests: XCTestCase {
    func testFileURLParsingPreservesLiteralNamesAndRejectsRemoteAndShellText() throws {
        let names = ["space name.txt", "中文.txt", "a'b.txt", "$HOME.txt", "`touch danger`.txt"]
        let urls = names.map { URL(fileURLWithPath: "/fixture/" + $0) }
        let parsed = FileDropRequest.locations(from: urls.map(\.absoluteString) + ["sftp://host/file", "$(touch danger)", "~/file"])
        XCTAssertEqual(parsed.map { $0.url.lastPathComponent }, names)
        let destination = FileLocation.local(URL(fileURLWithPath: "/captured"))
        let request = FileDropRequest.transfer(urlStrings: urls.map(\.absoluteString), kind: .move, destination: destination)
        XCTAssertEqual(request?.destinationDirectory, destination)
        XCTAssertEqual(request?.kind, .move)
        XCTAssertEqual(request?.sources, parsed)
    }
}
