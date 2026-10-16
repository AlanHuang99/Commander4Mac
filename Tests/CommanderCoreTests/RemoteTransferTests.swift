import XCTest
import CommanderCore
import Darwin

final class RemoteTransferTests: XCTestCase, @unchecked Sendable {
    private func run(_ request: TransferRequest, remote: MemoryRemote, journal: URL, decision: ConflictDecision = .skip,
                     token: OperationCancellation = .init()) async -> OperationResult {
        await RemoteTransferExecutor(remote: remote, journal: .init(directory: journal)).executeRequest(request, cancellation: token,
            resolveConflict: { conflict in
                XCTAssertFalse(conflict.supportsReplacement)
                return .init(decision)
            }, emit: { _ in })
    }
    func testWebDAVMoveMayChangeETagButCannotChangeContents() async throws {
        let f = try FixtureDirectory(); let source = try f.file("etag.txt", content: "original")
        for corrupt in [false, true] {
            let remote = MemoryRemote(webDAVRevisions: true, corruptAfterRename: corrupt)
            let result = await run(.init(kind: .copy, sources: [.local(source)], destinationDirectory: remote.root), remote: remote, journal: f.url.appendingPathComponent(UUID().uuidString))
            XCTAssertEqual(result.outcomes.first?.state, corrupt ? .partial : .completed, result.outcomes.first?.detail ?? "")
        }
    }
    func testFailedUploadAbortsChannelWithoutCommittingSpool() async throws {
        let f = try FixtureDirectory(); let file = try f.file("cancel", content: String(repeating: "x", count: 200000))
        let token = OperationCancellation(); let remote = MemoryRemote(cancelAfterWrite: token)
        _ = await run(.init(kind: .copy, sources: [.local(file)], destinationDirectory: remote.root), remote: remote, journal: f.url.appendingPathComponent("journal"), token: token)
        let aborted = await remote.aborted; let closed = await remote.closed
        XCTAssertEqual(aborted, 1); XCTAssertEqual(closed, 0)
    }
    func testUploadDownloadLiteralNamesAndKeepBothPreserveSources() async throws {
        let f = try FixtureDirectory(); let name = "literal #$ 中文.txt"
        let source = try f.file(name, content: "network fixture"); let localDest = try f.directory("dest")
        let remote = MemoryRemote(); let folder = remote.root
        let up = await run(.init(kind: .copy, sources: [.local(source)], destinationDirectory: folder), remote: remote, journal: f.url.appendingPathComponent("journal"))
        XCTAssertEqual(up.state, .completed)
        let uploaded = try folder.appending(name)
        let data = await remote.data(uploaded); XCTAssertEqual(data, Data("network fixture".utf8))
        try Data("existing".utf8).write(to: localDest.appendingPathComponent(name))
        let down = await run(.init(kind: .copy, sources: [uploaded], destinationDirectory: .local(localDest)), remote: remote,
                             journal: f.url.appendingPathComponent("journal"), decision: .keepBoth)
        XCTAssertEqual(down.state, .completed)
        XCTAssertEqual(try String(contentsOf: localDest.appendingPathComponent(name), encoding: .utf8), "existing")
        XCTAssertEqual(try String(contentsOf: localDest.appendingPathComponent("literal #$ 中文 copy.txt"), encoding: .utf8), "network fixture")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testLostRenameReplyDoesNotAskToKeepBothOrRetryAnotherDestination() async throws {
        let f = try FixtureDirectory(); let source = try f.file("file")
        let remote = MemoryRemote(failAfterRename: true)
        let conflicts = ConflictCounter()
        let journal = f.url.appendingPathComponent("journal")
        let result = await RemoteTransferExecutor(remote: remote, journal: .init(directory: journal)).executeRequest(
            .init(kind: .copy, sources: [.local(source)], destinationDirectory: remote.root), cancellation: .init(), resolveConflict: { _ in
                await conflicts.increment(); return .init(.keepBoth)
            }, emit: { _ in })
        XCTAssertEqual(result.outcomes.first?.state, .partial)
        let count = await conflicts.count; XCTAssertEqual(count, 0)
        XCTAssertEqual(try OperationJournal(directory: journal).recoverableJobs().first?.destination, try remote.root.appending("file").url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testDisappearingFinalDestinationIsNotReportedAsCompleted() async throws {
        let f = try FixtureDirectory(); let source = try f.file("file")
        let remote = MemoryRemote(removeAfterRename: true)
        let result = await run(.init(kind: .copy, sources: [.local(source)], destinationDirectory: remote.root), remote: remote, journal: f.url.appendingPathComponent("journal"))
        XCTAssertEqual(result.outcomes.first?.state, .partial)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testStreamingProgressIsCoalescedAndFinalTotalsRemainExact() async throws {
        let f = try FixtureDirectory(); let source = try f.file("large-progress", content: String(repeating: "x", count: 2_000_000))
        let remote = MemoryRemote(); let events = ProgressEvents()
        let result = await RemoteTransferExecutor(remote: remote, journal: .init(directory: f.url.appendingPathComponent("journal"))).executeRequest(
            .init(kind: .copy, sources: [.local(source)], destinationDirectory: remote.root), cancellation: .init(), resolveConflict: { _ in .init(.skip) }, emit: { event in
                if case .progress(let progress) = event { events.append(progress) }
            })
        XCTAssertEqual(result.state, .completed)
        let samples = events.values
        XCTAssertEqual(samples.last?.1.bytesCopied, 2_000_000)
        XCTAssertEqual(samples.last?.1.completedItems, 1)
        let nonFinal = samples.dropLast()
        XCTAssertTrue(zip(nonFinal, nonFinal.dropFirst()).allSatisfy { $1.0 - $0.0 >= 0.075 }, "Streaming updates must be coalesced, with a separate final flush")
    }
    func testUnsupportedBatchAndMoveRejectBeforeCreatingAnything() async throws {
        let f = try FixtureDirectory(); let file = try f.file("file"); let directory = try f.directory("folder"); try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("unsupported-link"), withDestinationURL: file)
        let remote = MemoryRemote()
        for request in [TransferRequest(kind: .copy, sources: [.local(file), .local(directory)], destinationDirectory: remote.root),
                        .init(kind: .move, sources: [.local(file)], destinationDirectory: remote.root)] {
            let result = await run(request, remote: remote, journal: f.url.appendingPathComponent("journal"))
            XCTAssertEqual(result.state, .failed)
        }
        let writes = await remote.writeCount; XCTAssertEqual(writes, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
    func testCanceledUploadRetainsSourceAndReportsRecoverableTemporaryFile() async throws {
        let f = try FixtureDirectory(); let file = try f.file("large", content: String(repeating: "x", count: 200_000))
        let token = OperationCancellation(); let remote = MemoryRemote(cancelAfterWrite: token)
        let journal = f.url.appendingPathComponent("journal")
        let result = await run(.init(kind: .copy, sources: [.local(file)], destinationDirectory: remote.root), remote: remote, journal: journal, token: token)
        XCTAssertEqual(result.state, .canceled)
        XCTAssertEqual(result.outcomes.first?.state, .partial)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let final = await remote.data(try remote.root.appending("large")); XCTAssertNil(final)
        XCTAssertEqual(try OperationJournal(directory: journal).recoverableJobs().count, 1)
    }
    func testSourceMutationAndRacingRemoteDestinationDoNotOverwrite() async throws {
        let f = try FixtureDirectory(); let file = try f.file("file", content: "original")
        let remote = MemoryRemote(mutateSource: file)
        let result = await run(.init(kind: .copy, sources: [.local(file)], destinationDirectory: remote.root), remote: remote, journal: f.url.appendingPathComponent("journal"))
        XCTAssertEqual(result.outcomes.first?.state, .partial)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "changed source")
        let remote2 = MemoryRemote(raceOnRename: true)
        let result2 = await run(.init(kind: .copy, sources: [.local(file)], destinationDirectory: remote2.root), remote: remote2,
                                journal: f.url.appendingPathComponent("journal2"), decision: .keepBoth)
        XCTAssertEqual(result2.state, .completed)
        let original = await remote2.data(try remote2.root.appending("file")); XCTAssertEqual(original, Data("racing destination".utf8))
        let both = await remote2.data(try remote2.root.appending("file copy")); XCTAssertEqual(both, Data("changed source".utf8))
    }
    func testDownloadFailureKeepsExistingDestinationAndCleansOwnedLocalStaging() async throws {
        let f = try FixtureDirectory(); let dest = try f.directory("dest"); let remote = MemoryRemote(failReads: true)
        let source = try remote.root.appending("large")
        await remote.seed(source, data: Data(repeating: 1, count: 200_000))
        let result = await run(.init(kind: .copy, sources: [source], destinationDirectory: .local(dest)), remote: remote, journal: f.url.appendingPathComponent("journal"))
        XCTAssertEqual(result.state, .failed)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dest.path).isEmpty)
        let retained = await remote.data(source); XCTAssertEqual(retained?.count, 200_000)
    }
}

private actor MemoryRemote: RemoteFileAccess {
    nonisolated let root: FileLocation
    private let webDAVRevisions: Bool; private let corruptAfterRename: Bool
    private(set) var aborted = 0; private(set) var closed = 0
    func abortChannel() { aborted += 1 }; func closeChannel() { closed += 1 }
    private var files: [FileLocation: Data] = [:]
    private var stamps: [FileLocation: Date] = [:]
    private var reads = 0
    private let cancelAfterWrite: OperationCancellation?
    private let mutateSource: URL?
    private let failReads: Bool
    private var raceOnRename: Bool
    private var failAfterRename: Bool
    private let removeAfterRename: Bool
    private(set) var writeCount = 0
    init(webDAVRevisions: Bool = false, corruptAfterRename: Bool = false, cancelAfterWrite: OperationCancellation? = nil, mutateSource: URL? = nil, failReads: Bool = false, raceOnRename: Bool = false, failAfterRename: Bool = false, removeAfterRename: Bool = false) {
        root = .remote(kind: webDAVRevisions ? .webdav : .sftp, profileID: UUID(), path: try! RemotePath("/test"))
        self.webDAVRevisions = webDAVRevisions; self.corruptAfterRename = corruptAfterRename
        self.cancelAfterWrite = cancelAfterWrite; self.mutateSource = mutateSource; self.failReads = failReads; self.raceOnRename = raceOnRename; self.failAfterRename = failAfterRename; self.removeAfterRename = removeAfterRename
    }
    func seed(_ location: FileLocation, data: Data) { files[location] = data; stamps[location] = Date(timeIntervalSince1970: 100) }
    func data(_ location: FileLocation) -> Data? { files[location] }
    func list(_ location: FileLocation, options: ListingOptions) async throws -> DirectorySnapshot { .init(location: location, entries: []) }
    func metadata(_ location: FileLocation) async throws -> RemoteFileMetadata? {
        if location == root { return .init(size: nil, permissions: UInt32(S_IFDIR) | 0o755, modified: .distantPast) }
        return files[location].map { .init(size: UInt64($0.count), permissions: UInt32(S_IFREG) | 0o600, modified: webDAVRevisions ? nil : stamps[location], revision: webDAVRevisions ? "\"" + location.remotePath!.rawValue + "\"" : nil) }
    }
    func openFile(_ location: FileLocation, writeExclusive: Bool) async throws -> any RemoteFileChannel {
        if writeExclusive {
            guard files[location] == nil else { throw FileOperationError.message("exists") }
            seed(location, data: Data())
        } else if files[location] == nil { throw FileOperationError.message("missing") }
        return MemoryChannel(server: self, location: location)
    }
    func read(_ location: FileLocation, offset: UInt64, length: UInt32) throws -> Data {
        reads += 1; if failReads && reads > 1 { throw FileOperationError.message("fixture disconnect") }
        let bytes = files[location]!
        let start = min(Int(offset), bytes.count); return bytes.subdata(in: start..<min(start + Int(length), bytes.count))
    }
    func write(_ location: FileLocation, data: Data, offset: UInt64) throws {
        guard files[location]!.count == Int(offset) else { throw FileOperationError.message("bad offset") }
        files[location]!.append(data); writeCount += 1
        cancelAfterWrite?.cancel()
        if let mutateSource { try Data("changed source".utf8).write(to: mutateSource) }
    }
    func rename(_ source: FileLocation, to destination: FileLocation) async throws {
        if raceOnRename { raceOnRename = false; seed(destination, data: Data("racing destination".utf8)) }
        guard files[destination] == nil else { throw FileOperationError.message("exists") }
        guard files[source] != nil else { throw FileOperationError.message("missing source") }
        files[destination] = files.removeValue(forKey: source); stamps[destination] = stamps.removeValue(forKey: source)
        if corruptAfterRename { files[destination] = Data(repeating: 120, count: files[destination]!.count) }
        if removeAfterRename { files.removeValue(forKey: destination) }
        if failAfterRename { failAfterRename = false; throw FileOperationError.message("lost rename reply") }
    }
    func createDirectory(_ location: FileLocation) async throws { }
}
private actor MemoryChannel: RemoteFileChannel {
    let server: MemoryRemote; let location: FileLocation
    init(server: MemoryRemote, location: FileLocation) { self.server = server; self.location = location }
    func read(offset: UInt64, length: UInt32) async throws -> Data { try await server.read(location, offset: offset, length: length) }
    func write(_ data: Data, offset: UInt64) async throws { try await server.write(location, data: data, offset: offset) }
    func close() async throws { await server.closeChannel() }
    func abort() async { await server.abortChannel() }
}

private actor ConflictCounter { var count = 0; func increment() { count += 1 } }

private final class ProgressEvents: @unchecked Sendable {
    private let lock = NSLock(); private var samples: [(TimeInterval, CopyProgress)] = []
    var values: [(TimeInterval, CopyProgress)] { lock.withLock { samples } }
    func append(_ value: CopyProgress) { lock.withLock { samples.append((ProcessInfo.processInfo.systemUptime, value)) } }
}
