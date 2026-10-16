import Foundation
import Darwin

public struct LocalOperationExecutor: Sendable {
    private let journal: OperationJournal
    private let backend: any FileOperationBackend
    private let copier: any FileCopying
    public init(journal: OperationJournal, backend: any FileOperationBackend = SystemFileOperationBackend(), copier: any FileCopying = LocalCopyEngine()) {
        self.journal = journal; self.backend = backend; self.copier = copier
    }
    public func execute(_ plan: TransferPlan, cancellation: OperationCancellation,
                        resolveConflict: @escaping @Sendable (TransferConflict) async -> ConflictResolution,
                        emit: @escaping @Sendable (OperationEvent) -> Void) async -> OperationResult {
        let policy = JobConflictPolicy(resolve: resolveConflict)
        var outcomes: [ItemOperationOutcome] = []
        emit(.state(.running))
        for item in plan.items {
            let outcome = await executeItem(item, plan: plan, cancellation: cancellation, policy: policy, emit: emit)
            outcomes.append(outcome); emit(.item(outcome))
        }
        let bad = outcomes.contains { $0.state == .failed || $0.state == .partial }
        let canceled = outcomes.contains { $0.state == .canceled } || (cancellation.isRequested && bad)
        let state: JobState = canceled ? .canceled : (bad ? .failed : .completed)
        emit(.state(state))
        return .init(jobID: plan.request.id, outcomes: outcomes, state: state)
    }
    private func executeItem(_ item: PlannedTransfer, plan: TransferPlan, cancellation: OperationCancellation,
                             policy: JobConflictPolicy, emit: @escaping @Sendable (OperationEvent) -> Void) async -> ItemOperationOutcome {
        var destination = item.destination
        var staging: URL?
        var ownedStageIdentity: FileIdentity?
        var preserveStaging = false
        var committed = false
        var record = JournalRecord(jobID: plan.request.id, itemID: item.id, source: item.source, destination: destination, staging: nil, phase: .planned)
        do {
            try cancellation.check()
            try await verifySource(item)
            try await verifyDestination(plan)
            try await write(record)
            var target = try await chooseTarget(item, destination: destination, jobID: plan.request.id, policy: policy, cancellation: cancellation)
            if target.skip { record.phase = .complete; try await write(record); return outcome(item, destination, .skipped) }
            destination = target.url; record.destination = destination
            try await verifyDestination(plan)
            // An exclusive same-volume rename preserves all metadata and never overwrites.
            let atomicMove = plan.request.kind == .move && target.existing == nil
                ? try await supportsAtomicMove(item.source.url, to: destination) : false
            if atomicMove {
                do {
                    try cancellation.check(); try await verifySource(item)
                    record.phase = .committing; try await write(record)
                    try await verifyDestination(plan)
                    try await rename(item.source.url, to: destination)
                    committed = true; record.phase = .complete; try await write(record)
                    return outcome(item, destination, .completed)
                } catch {
                    let ns = error as NSError
                    if committed { throw error }
                    if ns.domain == NSPOSIXErrorDomain && ns.code == Int(EEXIST) {
                        target = try await chooseTarget(item, destination: destination, jobID: plan.request.id, policy: policy, cancellation: cancellation)
                        if target.skip { record.phase = .complete; try await write(record); return outcome(item, destination, .skipped) }
                        destination = target.url; record.destination = destination
                    } else if ns.domain != NSPOSIXErrorDomain || ![Int(EXDEV), Int(ENOTSUP)].contains(ns.code) { throw error }
                }
            }
            let sourceManifest = try await manifest(item.source.url, cancellation: cancellation)
            let container = destination.deletingLastPathComponent().appendingPathComponent(".commander4mac-" + item.id.uuidString + ".partial")
            let temporary = container.appendingPathComponent("payload")
            record.staging = container; record.phase = .copying
            try await write(record)
            try await verifyDestination(plan)
            let containerIdentity = try await BlockingFileWorker.run {
                guard mkdir(container.path, 0o700) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                return try ItemVersion.read(at: container).identity
            }
            staging = container; ownedStageIdentity = containerIdentity
            try await copy(item.source.url, to: temporary, cancellation: cancellation, emit: emit)
            try cancellation.check()
            guard try await manifest(item.source.url, cancellation: cancellation) == sourceManifest else {
                throw FileOperationError.message("The source changed during copying. The source and existing destination have been retained.")
            }
            // Relative paths let the completed staging tree be checked after its rename.
            let completedManifest = plan.request.kind == .move ? try await manifest(temporary, cancellation: cancellation) : nil
            record.phase = .prepared; try await write(record)
            var finalized = false
            for _ in 0..<20 {
                try cancellation.check(); try await verifyDestination(plan)
                record.destination = destination; record.phase = .committing; try await write(record)
                if let expected = target.existing {
                    guard try await optionalVersion(destination) == expected else {
                        throw FileOperationError.message("The destination changed after confirmation. It has not been replaced.")
                    }
                    try await swap(temporary, destination)
                    committed = true; preserveStaging = true
                    guard try await version(temporary) == expected else {
                        throw FileOperationError.message("A concurrent destination change was preserved at \(temporary.path). Review both items before continuing.")
                    }
                    record.phase = .destinationReady; try await write(record)
                    try await removeOwnedStage(container, expecting: containerIdentity)
                    staging = nil; preserveStaging = false; finalized = true; break
                }
                do {
                    try await rename(temporary, to: destination)
                    committed = true
                    try await removeOwnedStage(container, expecting: containerIdentity)
                    staging = nil
                    record.phase = .destinationReady; record.staging = nil; try await write(record)
                    finalized = true; break
                } catch {
                    let ns = error as NSError
                    guard !committed, ns.domain == NSPOSIXErrorDomain, ns.code == Int(EEXIST) else { throw error }
                    target = try await chooseTarget(item, destination: destination, jobID: plan.request.id, policy: policy, cancellation: cancellation)
                    if target.skip {
                        try await removeOwnedStage(container, expecting: containerIdentity); staging = nil
                        record.phase = .complete; record.staging = nil; try await write(record)
                        return outcome(item, destination, .skipped)
                    }
                    destination = target.url
                }
            }
            guard finalized else { throw FileOperationError.message("The destination kept changing. Retry after other file operations finish.") }
            if plan.request.kind == .move {
                try cancellation.check()
                guard try await manifest(item.source.url, cancellation: cancellation) == sourceManifest else {
                    throw FileOperationError.message("The source changed before removal. The completed destination and source have been retained.")
                }
                try await verifyDestination(plan)
                guard try await manifest(destination, cancellation: cancellation) == completedManifest else {
                    throw FileOperationError.message("The completed destination changed before source removal. The source has been retained.")
                }
                try cancellation.check()
                try await removeSource(item.source.url, expecting: item.sourceVersion)
            }
            record.phase = .complete; record.staging = nil; try await write(record)
            return outcome(item, destination, .completed)
        } catch {
            if let staging, let identity = ownedStageIdentity, !preserveStaging {
                do { try await removeOwnedStage(staging, expecting: identity) }
                catch { preserveStaging = true }
            }
            let canceled = error is CancellationError || cancellation.isRequested
            let partial = committed || preserveStaging
            let detail = partial ? "\(error.localizedDescription) Review source, destination, and any recovery file: \(staging?.path ?? destination.path)" : error.localizedDescription
            record.phase = partial ? .recoveryRequired : .failed; record.detail = detail
            try? await write(record)
            return outcome(item, committed ? destination : nil, partial ? .partial : (canceled ? .canceled : .failed), detail: detail)
        }
    }
    private func chooseTarget(_ item: PlannedTransfer, destination: URL, jobID: UUID, policy: JobConflictPolicy,
                              cancellation: OperationCancellation) async throws -> TargetChoice {
        try cancellation.check()
        guard let existing = try await optionalVersion(destination) else { return .init(url: destination, existing: nil, skip: false) }
        let decision = await policy.resolve(.init(id: UUID(), jobID: jobID, source: item.source, destination: destination, isDirectory: item.isDirectory))
        try cancellation.check()
        switch decision.decision {
        case .cancel: cancellation.cancel(); throw CancellationError()
        case .skip: return .init(url: destination, existing: existing, skip: true)
        case .replace: return .init(url: destination, existing: existing, skip: false)
        case .keepBoth:
            for ordinal in 1...10_000 {
                let name = FileNameRules.keepBothCandidate(originalName: item.source.url.lastPathComponent, ordinal: ordinal)
                let candidate = destination.deletingLastPathComponent().appendingPathComponent(name)
                if try await optionalVersion(candidate) == nil { return .init(url: candidate, existing: nil, skip: false) }
            }
            throw FileOperationError.message("Could not find an unused destination name.")
        }
    }
    private func outcome(_ item: PlannedTransfer, _ destination: URL?, _ state: ItemOutcomeState, detail: String? = nil) -> ItemOperationOutcome {
        .init(id: item.id, source: item.source, destination: destination.map(FileLocation.local), state: state, detail: detail)
    }
    private func supportsAtomicMove(_ source: URL, to destination: URL) async throws -> Bool {
        try await BlockingFileWorker.run { backend.supportsAtomicMove(from: source, to: destination) }
    }
    private func version(_ url: URL) async throws -> ItemVersion { try await BlockingFileWorker.run { try backend.version(at: url) } }
    private func optionalVersion(_ url: URL) async throws -> ItemVersion? {
        do { return try await version(url) }
        catch {
            let ns = error as NSError
            if ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOENT) { return nil }
            throw error
        }
    }
    private func verifySource(_ item: PlannedTransfer) async throws {
        guard try await version(item.source.url) == item.sourceVersion else { throw FileOperationError.message("The source changed. Refresh the folder and retry.") }
    }
    private func verifyDestination(_ plan: TransferPlan) async throws {
        let identity = try await BlockingFileWorker.run { try LocationResolver.identity(at: plan.request.destinationDirectory.url.resolvingSymlinksInPath()) }
        guard identity == plan.destinationIdentity else { throw FileOperationError.message("The destination folder changed or disconnected. No further items were transferred.") }
    }
    private func write(_ record: JournalRecord) async throws { try await BlockingFileWorker.run { try journal.record(record) } }
    private func rename(_ source: URL, to destination: URL) async throws { try await BlockingFileWorker.run { try backend.renameExclusive(from: source, to: destination) } }
    private func swap(_ first: URL, _ second: URL) async throws { try await BlockingFileWorker.run { try backend.swap(first, second) } }
    private func removeSource(_ source: URL, expecting expected: ItemVersion) async throws { try await BlockingFileWorker.run { try backend.removeSource(at: source, expecting: expected) } }
    private func removeOwnedStage(_ url: URL, expecting identity: FileIdentity) async throws {
        try await BlockingFileWorker.run {
            do {
                let actual = try ItemVersion.read(at: url)
                guard actual.identity == identity, actual.isDirectory else {
                    throw FileOperationError.message("The staging folder changed identity. It has been left for review at \(url.path).")
                }
                try FileManager.default.removeItem(at: url)
            } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) { }
        }
    }
    private func copy(_ source: URL, to destination: URL, cancellation: OperationCancellation, emit: @escaping @Sendable (OperationEvent) -> Void) async throws {
        try await BlockingFileWorker.run { try copier.copy(source: source, stagingDestination: destination, cancellation: cancellation) { emit(.progress($0)) } }
    }
    private func manifest(_ root: URL, cancellation: OperationCancellation) async throws -> [String: ItemVersion] {
        try await BlockingFileWorker.run {
            var result: [String: ItemVersion] = [:]
            var pending = [(root, "")]
            while let (url, relativePath) = pending.popLast() {
                try cancellation.check()
                let version = try ItemVersion.read(at: url)
                result[relativePath] = version
                if version.isDirectory {
                    for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                        pending.append((child, relativePath + "/" + child.lastPathComponent))
                    }
                }
            }
            return result
        }
    }
}
private struct TargetChoice { let url: URL; let existing: ItemVersion?; let skip: Bool }
private actor JobConflictPolicy {
    private var all: ConflictResolution?
    private let resolver: @Sendable (TransferConflict) async -> ConflictResolution
    init(resolve: @escaping @Sendable (TransferConflict) async -> ConflictResolution) { resolver = resolve }
    func resolve(_ conflict: TransferConflict) async -> ConflictResolution {
        if let all { return all }
        let result = await resolver(conflict)
        if result.applyToAll && result.decision != .cancel { all = result }
        return result
    }
}
