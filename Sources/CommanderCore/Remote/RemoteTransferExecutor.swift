import Foundation
import Darwin
import CryptoKit

/// Cross-provider copies never delete a source. Fully local jobs use the existing executor.
public struct RemoteTransferExecutor: TransferExecuting {
    private let remote: any RemoteFileAccess
    private let journal: OperationJournal
    private let local: LocalOperationExecutor
    private let onVerifiedContent: (@Sendable (FileLocation, Data, TransferTreeManifest.Revision) -> Void)?
    public init(remote: any RemoteFileAccess, journal: OperationJournal) {
        self.init(remote: remote, journal: journal, onVerifiedContent: nil)
    }
    init(remote: any RemoteFileAccess, journal: OperationJournal, onVerifiedContent: (@Sendable (FileLocation, Data, TransferTreeManifest.Revision) -> Void)?) {
        self.onVerifiedContent = onVerifiedContent
        self.remote = remote; self.journal = journal; local = LocalOperationExecutor(journal: journal)
    }
    public func execute(_ plan: TransferPlan, cancellation: OperationCancellation,
                        resolveConflict: @escaping @Sendable (TransferConflict) async -> ConflictResolution,
                        emit: @escaping @Sendable (OperationEvent) -> Void) async -> OperationResult {
        await local.execute(plan, cancellation: cancellation, resolveConflict: resolveConflict, emit: emit)
    }
    public func executeRequest(_ request: TransferRequest, cancellation: OperationCancellation,
                               resolveConflict: @escaping @Sendable (TransferConflict) async -> ConflictResolution,
                               emit: @escaping @Sendable (OperationEvent) -> Void) async -> OperationResult {
        if request.destinationDirectory.isLocal && request.sources.allSatisfy(\.isLocal) {
            return await local.executeRequest(request, cancellation: cancellation, resolveConflict: resolveConflict, emit: emit)
        }
        let work = Task { await executeRemoteRequest(request, cancellation: cancellation, resolveConflict: resolveConflict, emit: emit) }
        let observer = cancellation.observe { work.cancel() }
        defer { cancellation.removeObserver(observer) }
        return await withTaskCancellationHandler { await work.value } onCancel: { cancellation.cancel() }
    }
    private func executeRemoteRequest(_ request: TransferRequest, cancellation: OperationCancellation,
                                      resolveConflict: @escaping @Sendable (TransferConflict) async -> ConflictResolution,
                                      emit: @escaping @Sendable (OperationEvent) -> Void) async -> OperationResult {
        var results: [ItemOperationOutcome] = []
        do {
            try cancellation.check()
            guard request.kind == .copy, !request.sources.isEmpty,
                  request.sources.allSatisfy({ $0.isLocal != request.destinationDirectory.isLocal }) else {
                throw FileOperationError.message("Remote Copy currently supports Copy between a local pane and a remote pane. Remote moves and server-to-server copies are not available.")
            }
            let sources = Array(Set(request.sources)).sorted { $0.url.absoluteString < $1.url.absoluteString }
            let treePlanner = TransferTreePlanner(remote: remote)
            var manifests: [TransferTreeManifest] = []; var total: UInt64 = 0; var entryCount = 0
            for source in sources {
                let manifest = try await treePlanner.plan(source)
                guard manifest.entries.count <= 100_000 - entryCount else { throw FileOperationError.message("This batch exceeds the 100,000 entry transfer limit.") }; entryCount += manifest.entries.count
                try await treePlanner.validateLocalNames(manifest, destinationDirectory: request.destinationDirectory)
                for entry in manifest.entries { let sum = total.addingReportingOverflow(entry.size ?? 0); guard !sum.overflow, sum.partialValue <= UInt64(Int64.max) else { throw FileOperationError.message("This batch exceeds the supported byte count.") }; total = sum.partialValue }
                manifests.append(manifest)
            }
            if manifests.contains(where: \.isDirectory) { return await RemoteTreeTransferExecutor(remote: remote, journal: journal).execute(request, manifests: manifests, cancellation: cancellation, resolve: resolveConflict, emit: emit) }
            var versions: [SourceVersion] = []
            // Complete preflight for the entire batch before creating any destination.
            for source in sources { versions.append(try await sourceVersion(source)) }
            let parentIdentity = try await localParentIdentity(request.destinationDirectory)
            try await verifyParent(request.destinationDirectory, identity: parentIdentity)
            emit(.state(.running))
            var all: ConflictResolution?
            var progress = CopyProgress()
            var lastProgressTime: TimeInterval = 0
            for (source, version) in zip(sources, versions) {
                let item = await copy(source, version: version, request: request, parentIdentity: parentIdentity, cancellation: cancellation,
                    applyAll: &all, progress: &progress, lastProgressTime: &lastProgressTime, resolve: resolveConflict, emit: emit)
                results.append(item); emit(.item(item))
            }
        } catch {
            results = request.sources.map { .init(source: $0, state: cancellation.isRequested ? .canceled : .failed, detail: error.localizedDescription) }
        }
        let failed = results.contains { $0.state == .failed || $0.state == .partial }
        let state: JobState = cancellation.isRequested ? .canceled : (failed ? .failed : .completed)
        emit(.state(state)); return .init(jobID: request.id, outcomes: results, state: state)
    }
    private typealias SourceVersion = TransferTreeManifest.Revision
    private func sourceVersion(_ location: FileLocation) async throws -> SourceVersion {
        if location.isLocal {
            let value = try await BlockingFileWorker.run { try ItemVersion.read(at: location.url) }
            guard value.mode & UInt16(S_IFMT) == UInt16(S_IFREG), value.size >= 0 else { throw unsupportedFile() }
            return .local(value)
        }
        guard let value = try await remote.metadata(location), value.isRegularFile, let size = value.size, size <= UInt64(Int64.max), (value.modified != nil || value.revision != nil) else { throw unsupportedFile() }
        return .remote(value)
    }
    private func unsupportedFile() -> FileOperationError { .message("Remote copies currently support regular files with size and modification metadata. Folders, packages, symlinks, and special files are not transferred.") }
    private func localParentIdentity(_ location: FileLocation) async throws -> FileIdentity? {
        guard location.isLocal else { return nil }
        return try await BlockingFileWorker.run { try LocationResolver.identity(at: location.url.resolvingSymlinksInPath()) }
    }
    private func verifyParent(_ location: FileLocation, identity: FileIdentity?) async throws {
        if location.isLocal {
            try await BlockingFileWorker.run {
                let version = try ItemVersion.read(at: location.url.resolvingSymlinksInPath())
                guard version.isDirectory, version.identity == identity else { throw FileOperationError.message("The local destination folder changed or disconnected.") }
            }
        } else {
            guard try await remote.metadata(location)?.kind == .directory else { throw FileOperationError.message("The remote destination folder is unavailable.") }
        }
    }
    private func exists(_ location: FileLocation) async throws -> Bool {
        if !location.isLocal { return try await remote.metadata(location) != nil }
        return try await BlockingFileWorker.run {
            do { _ = try ItemVersion.read(at: location.url); return true }
            catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) { return false }
        }
    }
    private func target(_ source: FileLocation, initial: FileLocation, request: TransferRequest, cancellation: OperationCancellation,
                        all: inout ConflictResolution?, resolve: @escaping @Sendable (TransferConflict) async -> ConflictResolution) async throws -> FileLocation? {
        try cancellation.check()
        guard try await exists(initial) else { return initial }
        let decision: ConflictResolution
        if let all { decision = all } else {
            decision = await resolve(.init(id: UUID(), jobID: request.id, source: source, destination: initial.url, isDirectory: false, supportsReplacement: false))
            if decision.applyToAll && decision.decision != .cancel { all = decision }
        }
        try cancellation.check()
        switch decision.decision {
        case .skip: return nil
        case .cancel: cancellation.cancel(); throw CancellationError()
        case .replace: throw FileOperationError.message("Safe remote replacement is not available. Use Keep Both or Skip. The existing item was retained.")
        case .keepBoth:
            for number in 1...10_000 {
                let name = FileNameRules.keepBothCandidate(originalName: source.url.lastPathComponent, ordinal: number)
                let candidate = try request.destinationDirectory.appending(name)
                if try await !exists(candidate) { return candidate }
            }
            throw FileOperationError.message("Could not find an unused destination name.")
        }
    }
    private func copy(_ source: FileLocation, version: SourceVersion, request: TransferRequest, parentIdentity: FileIdentity?,
                      cancellation: OperationCancellation, applyAll: inout ConflictResolution?, progress: inout CopyProgress, lastProgressTime: inout TimeInterval,
                      resolve: @escaping @Sendable (TransferConflict) async -> ConflictResolution,
                      emit: @escaping @Sendable (OperationEvent) -> Void) async -> ItemOperationOutcome {
        let itemID = UUID()
        var destination: FileLocation?
        var stage: FileLocation?
        var container: URL?
        var containerIdentity: FileIdentity?
        var remoteStagePossible = false
        var committed = false
        var record = JournalRecord(jobID: request.id, itemID: itemID, source: source, destination: request.destinationDirectory.url, staging: nil, phase: .planned)
        do {
            let initial = try request.destinationDirectory.appending(source.url.lastPathComponent)
            guard let selected = try await target(source, initial: initial, request: request, cancellation: cancellation, all: &applyAll, resolve: resolve) else {
                return .init(id: itemID, source: source, state: .skipped)
            }
            destination = selected
            try await verifyParent(request.destinationDirectory, identity: parentIdentity)
            guard try await sourceVersion(source) == version else { throw FileOperationError.message("The source changed before copying.") }
            record.destination = selected.url; record.phase = .copying
            if selected.isLocal {
                let privateFolder = request.destinationDirectory.url.appendingPathComponent(".commander4mac-\(itemID.uuidString).partial")
                record.staging = privateFolder; try await write(record)
                let identity = try await BlockingFileWorker.run {
                    guard mkdir(privateFolder.path, 0o700) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                    return try ItemVersion.read(at: privateFolder).identity
                }
                container = privateFolder; containerIdentity = identity
                stage = .local(privateFolder.appendingPathComponent("payload"))
            } else {
                stage = try request.destinationDirectory.appending(".commander4mac-\(itemID.uuidString).partial")
                record.staging = stage!.url; try await write(record)
            }
            let expectedSize: UInt64
            switch version { case .local(let value): expectedSize = UInt64(value.size); case .remote(let value): expectedSize = value.size! }
            var offset: UInt64 = 0
            var digest = SHA256()
            if source.isLocal {
                let sourceHandle = try await BlockingFileWorker.run { try Self.openReader(source.url, version: version) }
                defer { try? sourceHandle.close() }
                remoteStagePossible = true
                let writer = try await remote.openFile(stage!, writeExclusive: true)
                do {
                    while true {
                        try cancellation.check()
                        let bytes = try await BlockingFileWorker.run { try sourceHandle.read(upToCount: 65536) ?? Data() }
                        if bytes.isEmpty { break }
                        guard offset + UInt64(bytes.count) <= expectedSize else { throw FileOperationError.message("The source grew during copying.") }
                        try await writer.write(bytes, offset: offset)
                        digest.update(data: bytes)
                        offset += UInt64(bytes.count); progress.bytesCopied += Int64(bytes.count)
                        let now = ProcessInfo.processInfo.systemUptime
                        if now - lastProgressTime >= 0.08 { emit(.progress(progress)); lastProgressTime = now }
                    }
                    try await writer.close()
                } catch { await writer.abort(); throw error }
            } else {
                let stageURL = stage!.url
                let handle = try await BlockingFileWorker.run {
                    let fd = open(stageURL.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
                    guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                    return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                }
                let reader = try await remote.openFile(source, writeExclusive: false)
                do {
                    while true {
                        try cancellation.check()
                        let bytes = try await reader.read(offset: offset, length: 65536)
                        if bytes.isEmpty { break }
                        guard offset + UInt64(bytes.count) <= expectedSize else { throw FileOperationError.message("The remote source grew during copying.") }
                        try await BlockingFileWorker.run { try handle.write(contentsOf: bytes) }
                        digest.update(data: bytes)
                        offset += UInt64(bytes.count); progress.bytesCopied += Int64(bytes.count)
                        let now = ProcessInfo.processInfo.systemUptime
                        if now - lastProgressTime >= 0.08 { emit(.progress(progress)); lastProgressTime = now }
                    }
                    try await reader.close()
                    try await BlockingFileWorker.run { try handle.synchronize(); try handle.close() }
                } catch { await reader.abort(); try? handle.close(); throw error }
            }
            try cancellation.check()
            guard offset == expectedSize, try await sourceVersion(source) == version else { throw FileOperationError.message("The source changed or the copy was incomplete. The source has been retained.") }
            if let stage, !stage.isLocal {
                guard try await remote.metadata(stage)?.size == expectedSize else { throw FileOperationError.message("The server could not confirm the completed upload size.") }
            }
            let completedStage = try await sourceVersion(stage!)
            record.phase = .prepared; try await write(record)
            for _ in 0..<20 {
                try cancellation.check(); try await verifyParent(request.destinationDirectory, identity: parentIdentity)
                record.destination = destination!.url; record.phase = .committing; try await write(record)
                do {
                    let from = stage!; let to = destination!
                    if to.isLocal { try await BlockingFileWorker.run { try SystemFileOperationBackend().renameExclusive(from: from.url, to: to.url) } }
                    else { try await remote.rename(from, to: to) }
                    committed = true; remoteStagePossible = false; break
                } catch {
                    guard try await exists(stage!) else {
                        throw FileOperationError.message("The final rename could not be confirmed at \(destination!.url.absoluteString). Review that destination before retrying.")
                    }
                    guard try await exists(destination!) else { throw error }
                    guard let next = try await target(source, initial: destination!, request: request, cancellation: cancellation, all: &applyAll, resolve: resolve) else {
                        throw FileOperationError.message("The new collision was skipped after staging. Review any retained temporary upload.")
                    }
                    destination = next
                }
            }
            guard committed else { throw FileOperationError.message("The destination kept changing. The source was retained.") }
            try await verifyParent(request.destinationDirectory, identity: parentIdentity)
            let contentDigest = Data(digest.finalize())
            guard let verifiedVersion = try await verifyFinal(destination!, stage: completedStage, digest: contentDigest, cancellation: cancellation) else {
                throw FileOperationError.message("The finalized destination changed or could not be verified. The source was retained.")
            }
            if let container, let containerIdentity { try await cleanup(container, identity: containerIdentity) }
            record.phase = .complete; record.staging = nil; try await write(record)
            onVerifiedContent?(destination!, contentDigest, verifiedVersion)
            progress.completedItems += 1; emit(.progress(progress)); lastProgressTime = ProcessInfo.processInfo.systemUptime
            return .init(id: itemID, source: source, destination: destination, state: .completed,
                         detail: "Contents copied. Remote copies do not preserve permissions, timestamps, or extended metadata yet.")
        } catch {
            var retainedLocalStage = false
            if let container, let containerIdentity { do { try await cleanup(container, identity: containerIdentity) } catch { retainedLocalStage = true } }
            let partial = committed || remoteStagePossible || retainedLocalStage
            let detail = error.localizedDescription + (partial ? " Review the source, destination, and possible temporary file at \(record.staging?.absoluteString ?? record.destination.absoluteString)." : "")
            record.phase = partial ? .recoveryRequired : .failed; record.detail = detail; try? await write(record)
            return .init(id: itemID, source: source, destination: committed ? destination : nil,
                         state: partial ? .partial : (cancellation.isRequested ? .canceled : .failed), detail: detail)
        }
    }
    private func verifyFinal(_ destination: FileLocation, stage: SourceVersion, digest: Data, cancellation: OperationCancellation) async throws -> SourceVersion? {
        let final = try await sourceVersion(destination)
        guard destination.connectionProtocol == .webdav else { return final == stage ? final : nil }
        guard case .remote(let before) = stage, case .remote(let after) = final, before.size == after.size else { return nil }
        if let tag = before.revision, tag == after.revision { return final }
        // RFC 4918 permits validators to change during MOVE. Verify the bytes
        // when a server cannot carry its strong validator across publication.
        let reader = try await remote.openFile(destination, writeExclusive: false)
        do {
            var hash = SHA256(); var offset: UInt64 = 0
            while true {
                try cancellation.check(); let data = try await reader.read(offset: offset, length: 65536)
                if data.isEmpty { break }; guard offset + UInt64(data.count) <= after.size! else { await reader.abort(); return nil }
                hash.update(data: data); offset += UInt64(data.count)
            }
            try await reader.close()
            let unchanged = try await sourceVersion(destination) == final
            return offset == after.size && Data(hash.finalize()) == digest && unchanged ? final : nil
        } catch { await reader.abort(); throw error }
    }
    private static func openReader(_ url: URL, version: SourceVersion) throws -> FileHandle {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var info = stat()
        guard fstat(fd, &info) == 0, case .local(let expected) = version,
              FileIdentity(device: Int64(info.st_dev), inode: info.st_ino) == expected.identity else {
            close(fd); throw FileOperationError.message("The source changed before opening.")
        }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }
    private func cleanup(_ url: URL, identity: FileIdentity) async throws {
        try await BlockingFileWorker.run {
            guard try ItemVersion.read(at: url).identity == identity else { throw FileOperationError.message("The staging folder changed. It was retained.") }
            try FileManager.default.removeItem(at: url)
        }
    }
    private func write(_ record: JournalRecord) async throws { try await BlockingFileWorker.run { try journal.record(record) } }
}
