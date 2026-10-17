// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation
import XCTest
import CommanderCore

func assertNetworkTreeRoundTrip(remote: any RemoteFileAccess, root: FileLocation) async throws {
    let f = try FixtureDirectory(); let name = "tree #中文-" + UUID().uuidString
    let source = try f.directory(name); let nested = source.appendingPathComponent("nested")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
    try FileManager.default.createDirectory(at: source.appendingPathComponent("empty"), withIntermediateDirectories: false)
    let data = Data(String(repeating: "owned folder bytes", count: 12000).utf8)
    try data.write(to: nested.appendingPathComponent("literal #%$.bin")); try Data().write(to: source.appendingPathComponent("zero.txt"))
    let downloads = try f.directory("downloads"); let engine = RemoteTransferExecutor(remote: remote, journal: .init(directory: f.url.appendingPathComponent("journal")))
    let up = await engine.executeRequest(.init(kind: .copy, sources: [.local(source)], destinationDirectory: root), cancellation: .init(), resolveConflict: { _ in .init(.skip) }, emit: { _ in })
    XCTAssertEqual(up.state, .completed, up.outcomes.first?.detail ?? "")
    guard up.state == .completed else { return }
    let uploaded = try root.appending(name)
    let down = await engine.executeRequest(.init(kind: .copy, sources: [uploaded], destinationDirectory: .local(downloads)), cancellation: .init(), resolveConflict: { _ in .init(.skip) }, emit: { _ in })
    XCTAssertEqual(down.state, .completed, down.outcomes.first?.detail ?? "")
    guard down.state == .completed else { return }
    let output = downloads.appendingPathComponent(name)
    XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("nested/literal #%$.bin")), data)
    XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("zero.txt")).count, 0)
    XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("empty").path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
}
