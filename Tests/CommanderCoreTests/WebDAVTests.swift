// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import XCTest
import CommanderCore

final class WebDAVTests: XCTestCase {
    private func profile() -> ConnectionProfile {
        var p = ConnectionProfile(host: "dav.test", port: 443, username: "alice"); p.protocolKind = .webdav; p.basePath = "/dav/team"; return p
    }
    private func response(_ href: String, props: String, status: String = "HTTP/1.1 200 OK") -> String {
        "<d:response><d:href>\(href)</d:href><d:propstat><d:prop>\(props)</d:prop><d:status>\(status)</d:status></d:propstat></d:response>"
    }
    private func document(_ body: String) -> Data { Data("<d:multistatus xmlns:d='DAV:'>\(body)</d:multistatus>".utf8) }
    func testDepthOneParserPreservesLiteralNamesAndIgnoresFailedOptionalProperties() throws {
        let p = profile(); let endpoint = try WebDAVEndpoint(profile: p)
        let root = FileLocation.webdav(profileID: p.id, path: try RemotePath("/"))
        let data = document(response("/dav/team/", props: "<d:resourcetype><d:collection/></d:resourcetype>") + response("/dav/team/a%20%23%25%E4%B8%AD.txt", props: "<d:resourcetype/><d:getcontentlength>12</d:getcontentlength><d:getetag>&quot;v1&quot;</d:getetag>"))
        let parsed = try WebDAVListing.parse(data, endpoint: endpoint, location: root, depth: 1)
        XCTAssertEqual(parsed.entries.map(\.name), ["a #%中.txt"])
        XCTAssertEqual(parsed.entries.first?.byteSize, 12)
        let failed = document(response("/dav/team/b.txt", props: "<d:resourcetype/><d:getcontentlength>999</d:getcontentlength>", status: "HTTP/1.1 403 Forbidden"))
        XCTAssertThrowsError(try WebDAVListing.parse(failed, endpoint: endpoint, location: root, depth: 1))
    }
    func testForeignEscapingAliasedAndOverdeepHrefsAreRejected() throws {
        let p = profile(); let endpoint = try WebDAVEndpoint(profile: p)
        let root = FileLocation.webdav(profileID: p.id, path: try RemotePath("/"))
        for href in ["https://evil.test/dav/team/a", "/dav/team/%2e%2e/escape", "/dav/team/a%2fb", "/dav/team/sub/a", "/outside/a", "/dav/team/a?secret=x", "/dav/team/a%5cb", "/dav//team/a", "/dav/team//a", "/dav/team/a//"] {
            XCTAssertThrowsError(try WebDAVListing.parse(document(response(href, props: "<d:resourcetype/>")), endpoint: endpoint, location: root, depth: 1), href)
        }
        let dup = document(response("/dav/team/a", props: "<d:resourcetype/>") + response("/dav/team/%61", props: "<d:resourcetype/>"))
        XCTAssertThrowsError(try WebDAVListing.parse(dup, endpoint: endpoint, location: root, depth: 1))
    }
    func testOutgoingPathsRejectNamesTheListingParserCannotRepresent() throws {
        let endpoint = try WebDAVEndpoint(profile: profile())
        for path in ["/bad\\name", "/bad\nname"] { XCTAssertThrowsError(try endpoint.url(RemotePath(path))) }
    }
    func testXMLDeclarationsAndOversizeBodiesAreRejected() throws {
        let p = profile(); let endpoint = try WebDAVEndpoint(profile: p)
        let root = FileLocation.webdav(profileID: p.id, path: try RemotePath("/"))
        let entity = Data("<!DOCTYPE x [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><d:multistatus xmlns:d='DAV:'>&x;</d:multistatus>".utf8)
        XCTAssertThrowsError(try WebDAVListing.parse(entity, endpoint: endpoint, location: root, depth: 1))
        XCTAssertThrowsError(try WebDAVListing.parse(Data(repeating: 32, count: 8_388_609), endpoint: endpoint, location: root, depth: 1))
    }
}
