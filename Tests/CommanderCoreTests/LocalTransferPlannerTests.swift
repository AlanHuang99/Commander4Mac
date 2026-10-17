// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import XCTest
import CommanderCore

final class LocalTransferPlannerTests: XCTestCase {
    func testPlanCapturesSourceAndDestinationWithoutMutation() throws {
        let fixture = try FixtureDirectory()
        let source = try fixture.file("report.txt", content: "original")
        let destination = try fixture.directory("destination")
        let plan = try LocalTransferPlanner().plan(.init(kind: .copy, sources: [.local(source)], destinationDirectory: .local(destination)))
        XCTAssertEqual(plan.items.count, 1)
        XCTAssertEqual(plan.items[0].destination.path, destination.appendingPathComponent("report.txt").path)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "original")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.items[0].destination.path))
    }
    func testRejectsSelfCopyAndDescendantDestination() throws {
        let fixture = try FixtureDirectory()
        let directory = try fixture.directory("source")
        let child = directory.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        XCTAssertThrowsError(try LocalTransferPlanner().plan(.init(kind: .copy, sources: [.local(directory)], destinationDirectory: .local(fixture.url))))
        XCTAssertThrowsError(try LocalTransferPlanner().plan(.init(kind: .move, sources: [.local(directory)], destinationDirectory: .local(child))))
    }
    func testRejectsHardLinkToSameDestinationItem() throws {
        let fixture = try FixtureDirectory()
        let source = try fixture.file("a.txt")
        let destination = try fixture.directory("destination")
        try FileManager.default.linkItem(at: source, to: destination.appendingPathComponent("a.txt"))
        XCTAssertThrowsError(try LocalTransferPlanner().plan(.init(kind: .copy, sources: [.local(source)], destinationDirectory: .local(destination))))
    }
    func testRejectsOverlappingSourceRootsAndAllowsSymlinkAsLink() throws {
        let fixture = try FixtureDirectory()
        let directory = try fixture.directory("source")
        let file = directory.appendingPathComponent("child.txt")
        try Data("child".utf8).write(to: file)
        let destination = try fixture.directory("destination")
        XCTAssertThrowsError(try LocalTransferPlanner().plan(.init(kind: .copy, sources: [.local(directory), .local(file)], destinationDirectory: .local(destination))))
        let link = fixture.url.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)
        let plan = try LocalTransferPlanner().plan(.init(kind: .copy, sources: [.local(link)], destinationDirectory: .local(destination)))
        XCTAssertFalse(plan.items[0].isDirectory)
    }
}
