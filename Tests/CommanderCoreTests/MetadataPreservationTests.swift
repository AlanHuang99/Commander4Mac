// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import XCTest
import CommanderCore
import Darwin

final class MetadataPreservationTests: XCTestCase {
    func testProgressIsThrottledForManySmallFilesAndEndsWithActualCounts() throws {
        let f = try FixtureDirectory(); let source = try f.directory("many")
        for index in 0..<128 { try Data("x".utf8).write(to: source.appendingPathComponent("file-\(index)")) }
        let progress = ProgressCapture()
        try LocalCopyEngine().copy(source: source, stagingDestination: f.url.appendingPathComponent("copied"), cancellation: .init()) { progress.add($0) }
        let events = progress.values
        XCTAssertLessThan(events.count, 100, "Small-file completion must not flood the UI with one update per file")
        XCTAssertEqual(events.last?.completedItems, 128)
        XCTAssertEqual(events.last?.bytesCopied, 128)
    }

    func testCopyPreservesPermissionsDateAndExtendedAttributes() throws {
        let f = try FixtureDirectory(); let source = try f.file("source.txt", content: "payload")
        let payload = Data("extended-metadata".utf8)
        for name in ["com.commander4mac.fixture", "com.apple.ResourceFork"] {
            let status = payload.withUnsafeBytes { setxattr(source.path, name, $0.baseAddress, payload.count, 0, 0) }
            XCTAssertEqual(status, 0)
        }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.posixPermissions: 0o640, .modificationDate: date], ofItemAtPath: source.path)
        let target = f.url.appendingPathComponent("copied.txt")
        try LocalCopyEngine().copy(source: source, stagingDestination: target, cancellation: .init(), progress: { _ in })
        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o640)
        XCTAssertEqual((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0, date.timeIntervalSince1970, accuracy: 0.01)
        for name in ["com.commander4mac.fixture", "com.apple.ResourceFork"] {
            var buffer = Data(count: payload.count)
            let length = buffer.withUnsafeMutableBytes { getxattr(target.path, name, $0.baseAddress, payload.count, 0, 0) }
            XCTAssertEqual(length, payload.count); XCTAssertEqual(buffer, payload)
        }
    }
    func testCopyPreservesExplicitACL() throws {
        let f = try FixtureDirectory(); let source = try f.file("acl.txt"); let target = f.url.appendingPathComponent("copy.txt")
        func run(_ path: String, _ arguments: [String]) throws -> (Int32, String) {
            let process = Process(); process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
            try process.run(); process.waitUntilExit()
            return (process.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        }
        let setup = try run("/bin/chmod", ["+a", "user:" + NSUserName() + " allow read,write", source.path])
        guard setup.0 == 0 else { throw XCTSkip("ACL fixture is unsupported: " + setup.1) }
        try LocalCopyEngine().copy(source: source, stagingDestination: target, cancellation: .init(), progress: { _ in })
        let before = try run("/bin/ls", ["-lde", source.path]).1.split(separator: "\n").dropFirst().map(String.init)
        let after = try run("/bin/ls", ["-lde", target.path]).1.split(separator: "\n").dropFirst().map(String.init)
        XCTAssertFalse(before.isEmpty)
        XCTAssertEqual(after, before)
    }
    func testRecursiveCopyPreservesPackageContentsAndBrokenSymlink() throws {
        let f = try FixtureDirectory(); let source = try f.directory("Example.app")
        try Data("package content".utf8).write(to: source.appendingPathComponent("file"))
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("link").path, withDestinationPath: "/missing/fixture-target")
        let target = f.url.appendingPathComponent("copy.app")
        try LocalCopyEngine().copy(source: source, stagingDestination: target, cancellation: .init(), progress: { _ in })
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("file"), encoding: .utf8), "package content")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: target.appendingPathComponent("link").path), "/missing/fixture-target")
    }
    func testJournalFindsIncompleteRecordsWithoutReplayingThem() throws {
        let f = try FixtureDirectory(); let source = try f.file("source.txt")
        let destination = f.url.appendingPathComponent("destination.txt")
        let journal = OperationJournal(directory: try f.directory("journal"))
        var record = JournalRecord(jobID: UUID(), itemID: UUID(), source: .local(source), destination: destination, staging: nil, phase: .copying)
        try journal.record(record)
        XCTAssertEqual(try journal.recoverableJobs().count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        record.phase = .complete; try journal.record(record)
        XCTAssertEqual(try journal.recoverableJobs().count, 0)
    }
}

private final class ProgressCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [CopyProgress] = []
    func add(_ value: CopyProgress) { lock.withLock { captured.append(value) } }
    var values: [CopyProgress] { lock.withLock { captured } }
}
