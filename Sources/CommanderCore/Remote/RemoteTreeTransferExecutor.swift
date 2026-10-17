// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation
import Darwin
import CryptoKit

/// Root staging avoids exposing an incomplete tree at its final name.
struct RemoteTreeTransferExecutor: Sendable {
    let remote: any RemoteFileAccess; let journal: OperationJournal
    func execute(_ request: TransferRequest, manifests: [TransferTreeManifest], cancellation: OperationCancellation,
                 resolve: @escaping @Sendable (TransferConflict) async -> ConflictResolution,
                 emit: @escaping @Sendable (OperationEvent) -> Void) async -> OperationResult {
        var outcomes: [ItemOperationOutcome] = []; var applyAll: ConflictResolution?
        let progress = TreeProgress(); emit(.state(.running))
        for manifest in manifests {
            let outcome: ItemOperationOutcome
            if manifest.isDirectory {
                outcome = await copyTree(manifest, request: request, cancellation: cancellation, applyAll: &applyAll, progress: progress, resolve: resolve, emit: emit)
            } else {
                let base = progress.value
                let result = await RemoteTransferExecutor(remote: remote, journal: journal).executeRequest(.init(id: request.id, kind: .copy, sources: [manifest.source], destinationDirectory: request.destinationDirectory), cancellation: cancellation, resolveConflict: resolve, emit: { event in
                    if case .progress(let p) = event { emit(.progress(progress.update(p, base: base))) }
                })
                outcome = result.outcomes.first ?? .init(source: manifest.source, state: .failed, detail: "The transfer did not return an outcome.")
            }
            outcomes.append(outcome); emit(.item(outcome))
        }
        let failed = outcomes.contains { $0.state == .failed || $0.state == .partial }
        let state: JobState = cancellation.isRequested ? .canceled : (failed ? .failed : .completed)
        emit(.state(state)); return .init(jobID: request.id, outcomes: outcomes, state: state)
    }
    private func copyTree(_ manifest: TransferTreeManifest, request: TransferRequest, cancellation: OperationCancellation,
                          applyAll: inout ConflictResolution?, progress: TreeProgress,
                          resolve: @escaping @Sendable (TransferConflict) async -> ConflictResolution,
                          emit: @escaping @Sendable (OperationEvent) -> Void) async -> ItemOperationOutcome {
        let id = UUID(); let source = manifest.source; let parent = request.destinationDirectory
        let planner = TransferTreePlanner(remote: remote); let digests = TreeDigests()
        var record = JournalRecord(jobID: request.id, itemID: id, source: source, destination: parent.url, staging: nil, phase: .planned, endpointSnapshot: await remote.endpointSnapshot(source.isLocal ? request.destinationDirectory : source))
        var destination: FileLocation?; var stage: FileLocation?; var container: URL?; var containerIdentity: FileIdentity?
        var remoteStagePossible = false; var published = false
        do {
            try cancellation.check(); try Task.checkCancellation()
            guard let selected = try await target(source, initial: parent.appending(source.title), request: request, cancellation: cancellation, all: &applyAll, resolve: resolve) else { return .init(id: id, source: source, state: .skipped) }
            destination = selected
            let parentVersion = try await directoryIdentity(parent)
            guard try await planner.plan(source) == manifest else { throw changed() }
            record.destination = selected.url; record.phase = .copying
            let temporary = try parent.appending(".commander4mac-\(id.uuidString).partial")
            record.staging = temporary.url; try await write(record)
            if parent.isLocal {
                let identity = try await BlockingFileWorker.run {
                    guard mkdir(temporary.url.path, 0o700) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                    return try ItemVersion.read(at: temporary.url).identity
                }
                container = temporary.url; containerIdentity = identity; stage = try temporary.appending("payload")
                try await makeDirectory(stage!)
            } else { stage = temporary; remoteStagePossible = true; try await remote.createDirectory(temporary) }
            for entry in manifest.entries where entry.relativePath.rawValue != "/" {
                try cancellation.check(); try Task.checkCancellation(); try await verifyDirectory(parent, identity: parentVersion)
                let output = try manifest.location(entry, under: stage!)
                if entry.kind == .directory { try await makeDirectory(output); continue }
                let input = try manifest.location(entry, under: source); let base = progress.value
                let child = await RemoteTransferExecutor(remote: remote, journal: journal, onVerifiedContent: { location, digest, revision in digests.set(digest, revision: revision, at: location) }).executeRequest(.init(id: request.id, kind: .copy, sources: [input], destinationDirectory: output.parent), cancellation: cancellation, resolveConflict: { _ in .init(.cancel) }, emit: { event in
                    if case .progress(let p) = event { emit(.progress(progress.update(p, base: base))) }
                })
                guard child.outcomes.count == 1, child.outcomes[0].state == .completed else { throw FileOperationError.message(child.outcomes.first?.detail ?? "A file in the tree could not be copied.") }
            }
            try cancellation.check()
            guard try await planner.plan(source) == manifest else { throw changed() }
            let staged = try await planner.plan(stage!)
            guard manifest.hasSameStructure(as: staged) else { throw FileOperationError.message("The staged folder structure could not be verified.") }
            for entry in staged.entries where entry.kind == .file {
                let location = try staged.location(entry, under: stage!)
                guard digests.get(location)?.1 == entry.revision else { throw changed() }
            }
            record.phase = .prepared; try await write(record)
            for _ in 0..<20 {
                try cancellation.check(); try await verifyDirectory(parent, identity: parentVersion)
                record.destination = destination!.url; record.phase = .committing; try await write(record)
                do {
                    if parent.isLocal {
                        let from = stage!.url; let to = destination!.url
                        try await BlockingFileWorker.run { try SystemFileOperationBackend().renameExclusive(from: from, to: to) }
                    } else { try await remote.rename(stage!, to: destination!) }
                    published = true; remoteStagePossible = false; break
                } catch {
                    guard try await exists(stage!) else { throw FileOperationError.message("The final folder rename could not be confirmed. Review the destination before retrying.") }
                    guard try await exists(destination!) else { throw error }
                    guard let next = try await target(source, initial: destination!, request: request, cancellation: cancellation, all: &applyAll, resolve: resolve) else { throw FileOperationError.message("The root collision was skipped after staging.") }
                    destination = next
                }
            }
            guard published else { throw FileOperationError.message("The destination kept changing.") }
            try await verifyDirectory(parent, identity: parentVersion)
            let final = try await planner.plan(destination!)
            guard staged.hasSameStructure(as: final) else { throw FileOperationError.message("The finalized folder structure changed or could not be verified.") }
            for (before, after) in zip(staged.entries, final.entries) where before.kind == .file {
                try cancellation.check()
                if destination!.connectionProtocol == .webdav {
                    guard case .remote(let b) = before.revision, case .remote(let a) = after.revision else { throw changed() }
                    if let tag = b.revision, tag == a.revision { continue }
                    let old = try staged.location(before, under: stage!); let new = try final.location(after, under: destination!)
                    guard let digest = digests.get(old)?.0, try await verifyDigest(new, size: after.size!, digest: digest, revision: after.revision, planner: planner, cancellation: cancellation) else { throw changed() }
                } else if before.revision != after.revision { throw changed() }
            }
            if let container, let containerIdentity { try await cleanup(container, identity: containerIdentity) }
            record.phase = .complete; record.staging = nil; try await write(record)
            return .init(id: id, source: source, destination: destination, state: .completed, detail: "Folder contents and structure copied. Permissions, dates, and extended metadata are not preserved across servers.")
        } catch {
            var retainedLocal = false
            if let container, let containerIdentity { do { try await cleanup(container, identity: containerIdentity) } catch { retainedLocal = true } }
            let partial = published || remoteStagePossible || retainedLocal
            let detail = error.localizedDescription + (partial ? " Source retained. Review the destination and temporary tree at \(record.staging?.absoluteString ?? record.destination.absoluteString)." : " Source retained.")
            record.phase = partial ? .recoveryRequired : .failed; record.detail = detail; try? await write(record)
            return .init(id: id, source: source, destination: published ? destination : nil, state: partial ? .partial : (cancellation.isRequested ? .canceled : .failed), detail: detail)
        }
    }
    private func verifyDigest(_ location: FileLocation, size: UInt64, digest: Data, revision: TransferTreeManifest.Revision, planner: TransferTreePlanner, cancellation: OperationCancellation) async throws -> Bool {
        let reader = try await remote.openFile(location, writeExclusive: false)
        do {
            var hash = SHA256(); var offset: UInt64 = 0
            while true { try cancellation.check(); let data = try await reader.read(offset: offset, length: 65536); if data.isEmpty { break }; guard offset + UInt64(data.count) <= size else { await reader.abort(); return false }; hash.update(data: data); offset += UInt64(data.count) }
            try await reader.close(); let current = try await planner.plan(location)
            return offset == size && Data(hash.finalize()) == digest && current.entries.first?.revision == revision
        } catch { await reader.abort(); throw error }
    }
    private func target(_ source: FileLocation, initial: FileLocation, request: TransferRequest, cancellation: OperationCancellation, all: inout ConflictResolution?, resolve: @escaping @Sendable (TransferConflict) async -> ConflictResolution) async throws -> FileLocation? {
        try cancellation.check(); guard try await exists(initial) else { return initial }
        let decision: ConflictResolution
        if let all { decision = all } else { decision = await resolve(.init(id: UUID(), jobID: request.id, source: source, destination: initial.url, isDirectory: true, supportsReplacement: false)); if decision.applyToAll && decision.decision != .cancel { all = decision } }
        try cancellation.check()
        switch decision.decision {
        case .skip: return nil
        case .cancel: cancellation.cancel(); throw CancellationError()
        case .replace: throw FileOperationError.message("Folder replacement and merging are not available for remote copies. Use Keep Both or Skip.")
        case .keepBoth:
            for number in 1...10_000 { let candidate = try request.destinationDirectory.appending(FileNameRules.keepBothCandidate(originalName: source.title, ordinal: number)); if try await !exists(candidate) { return candidate } }
            throw FileOperationError.message("Could not find an unused folder name.")
        }
    }
    private func exists(_ location: FileLocation) async throws -> Bool {
        if !location.isLocal { return try await remote.metadata(location) != nil }
        return try await BlockingFileWorker.run { do { _ = try ItemVersion.read(at: location.url); return true } catch let e as NSError where e.domain == NSPOSIXErrorDomain && e.code == Int(ENOENT) { return false } }
    }
    private func directoryIdentity(_ location: FileLocation) async throws -> FileIdentity? {
        if location.isLocal { return try await BlockingFileWorker.run { let value = try ItemVersion.read(at: location.url.resolvingSymlinksInPath()); guard value.isDirectory else { throw changed() }; return value.identity } }
        guard try await remote.metadata(location)?.kind == .directory else { throw changed() }; return nil
    }
    private func verifyDirectory(_ location: FileLocation, identity: FileIdentity?) async throws { guard try await directoryIdentity(location) == identity else { throw changed() } }
    private func makeDirectory(_ location: FileLocation) async throws {
        if location.isLocal { try await BlockingFileWorker.run { guard mkdir(location.url.path, 0o700) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) } } }
        else { try await remote.createDirectory(location) }
    }
    private func cleanup(_ url: URL, identity: FileIdentity) async throws { try await BlockingFileWorker.run { guard try ItemVersion.read(at: url).identity == identity else { throw changed() }; try FileManager.default.removeItem(at: url) } }
    private func write(_ record: JournalRecord) async throws { try await BlockingFileWorker.run { try journal.record(record) } }
    private func changed() -> FileOperationError { .message("A source, destination, or staged item changed or became unavailable. The copy cannot be verified.") }
}
private final class TreeProgress: @unchecked Sendable {
    private let lock = NSLock(); private var progress = CopyProgress()
    var value: CopyProgress { lock.withLock { progress } }
    func update(_ value: CopyProgress, base: CopyProgress) -> CopyProgress { lock.withLock { progress = .init(bytesCopied: base.bytesCopied + value.bytesCopied, completedItems: base.completedItems + value.completedItems); return progress } }
}
private final class TreeDigests: @unchecked Sendable {
    private let lock = NSLock(); private var values: [FileLocation: (Data, TransferTreeManifest.Revision)] = [:]
    func set(_ data: Data, revision: TransferTreeManifest.Revision, at location: FileLocation) { lock.withLock { values[location] = (data, revision) } }
    func get(_ location: FileLocation) -> (Data, TransferTreeManifest.Revision)? { lock.withLock { values[location] } }
}
