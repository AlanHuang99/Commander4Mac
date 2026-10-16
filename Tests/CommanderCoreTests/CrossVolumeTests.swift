import XCTest
import CommanderCore

final class CrossVolumeTests: XCTestCase, @unchecked Sendable {
    func testRealCrossVolumeMoveCopiesThenRemovesSource() async throws {
        guard let mount = ProcessInfo.processInfo.environment["COMMANDER_TEST_SECOND_VOLUME"] else {
            throw XCTSkip("Run script/test_cross_volume.sh for the disposable-volume integration check.")
        }
        let sourceFixture = try FixtureDirectory()
        let source = try sourceFixture.directory("source-tree")
        try Data("cross-volume contents".utf8).write(to: source.appendingPathComponent("child.txt"))
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("link").path, withDestinationPath: "child.txt")
        let destination = URL(fileURLWithPath: mount).appendingPathComponent("Commander4MacTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: destination) }
        XCTAssertNotEqual(try LocationResolver.identity(at: source).device, try LocationResolver.identity(at: destination).device)
        let plan = try LocalTransferPlanner().plan(.init(kind: .move, sources: [.local(source)], destinationDirectory: .local(destination)))
        let journal = OperationJournal(directory: sourceFixture.url.appendingPathComponent("journal"))
        let result = await LocalOperationExecutor(journal: journal).execute(plan, cancellation: .init(), resolveConflict: { _ in .init(.skip) }, emit: { _ in })
        XCTAssertEqual(result.state, .completed, result.outcomes.first?.detail ?? "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        let copied = destination.appendingPathComponent("source-tree")
        XCTAssertEqual(try String(contentsOf: copied.appendingPathComponent("child.txt"), encoding: .utf8), "cross-volume contents")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: copied.appendingPathComponent("link").path), "child.txt")
    }
}
