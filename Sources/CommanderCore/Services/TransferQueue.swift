import Foundation

public protocol TransferExecuting: Sendable {
    func execute(_ plan: TransferPlan, cancellation: OperationCancellation,
                 resolveConflict: @escaping @Sendable (TransferConflict) async -> ConflictResolution,
                 emit: @escaping @Sendable (OperationEvent) -> Void) async -> OperationResult
}
extension LocalOperationExecutor: TransferExecuting {}

public actor TransferQueue {
    private let executor: any TransferExecuting
    public let gate: OperationGate
    private var jobs: [JobSnapshot] = []
    private var pending: [UUID] = []
    private var processing = false
    private var tokens: [UUID: OperationCancellation] = [:]
    private var conflicts: [UUID: (UUID, CheckedContinuation<ConflictResolution, Never>)] = [:]
    private var observers: [UUID: AsyncStream<[JobSnapshot]>.Continuation] = [:]
    public init(executor: any TransferExecuting, gate: OperationGate = .init()) { self.executor = executor; self.gate = gate }
    @discardableResult public func enqueue(_ request: TransferRequest) -> UUID {
        guard !jobs.contains(where: { $0.id == request.id }) else { return request.id }
        jobs.append(.init(request: request)); pending.append(request.id); tokens[request.id] = .init()
        publish()
        if !processing { processing = true; Task { await drain() } }
        return request.id
    }
    public func currentSnapshots() -> [JobSnapshot] { jobs }
    public func snapshots() -> AsyncStream<[JobSnapshot]> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<[JobSnapshot]>.makeStream(bufferingPolicy: .bufferingNewest(1))
        observers[id] = continuation; continuation.yield(jobs)
        continuation.onTermination = { [weak self] _ in Task { await self?.removeObserver(id) } }
        return stream
    }
    public func cancel(jobID: UUID) {
        guard let index = index(jobID), !jobs[index].state.isTerminal else { return }
        tokens[jobID]?.cancel()
        if jobs[index].state == .queued {
            pending.removeAll { $0 == jobID }; jobs[index].state = .canceled; tokens.removeValue(forKey: jobID)
        } else {
            jobs[index].state = .cancelRequested
            if let (_, continuation) = conflicts.removeValue(forKey: jobID) {
                jobs[index].pendingConflict = nil; continuation.resume(returning: .init(.cancel))
            }
        }
        publish()
    }
    public func resolveConflict(jobID: UUID, conflictID: UUID, resolution: ConflictResolution) {
        guard let (expected, continuation) = conflicts[jobID], expected == conflictID else { return }
        conflicts.removeValue(forKey: jobID)
        if let index = index(jobID) { jobs[index].pendingConflict = nil; jobs[index].state = .running }
        continuation.resume(returning: resolution); publish()
    }
    public func dismissFinished() { jobs.removeAll { $0.state.isTerminal }; publish() }
    private func drain() async {
        while !pending.isEmpty {
            let id = pending.removeFirst()
            guard let initial = jobs.first(where: { $0.id == id }), let token = tokens[id], !token.isRequested else { continue }
            setState(id, .planning)
            await gate.acquire()
            let result: OperationResult
            do {
                try token.check()
                let plan = try await BlockingFileWorker.run { try LocalTransferPlanner().plan(initial.request) }
                result = await executor.execute(plan, cancellation: token, resolveConflict: { [weak self] conflict in
                    await self?.ask(conflict, cancellation: token) ?? .init(.cancel)
                }, emit: { [weak self] event in Task { await self?.handle(event, jobID: id) } })
            } catch {
                let state: JobState = token.isRequested ? .canceled : .failed
                result = .init(jobID: id, outcomes: initial.request.sources.map {
                    .init(source: $0, state: state == .canceled ? .canceled : .failed, detail: error.localizedDescription)
                }, state: state)
            }
            await gate.release()
            if let index = index(id) {
                jobs[index].state = result.state; jobs[index].outcomes = result.outcomes; jobs[index].pendingConflict = nil
            }
            tokens.removeValue(forKey: id); publish()
        }
        processing = false
    }
    private func ask(_ conflict: TransferConflict, cancellation: OperationCancellation) async -> ConflictResolution {
        guard !cancellation.isRequested, let index = index(conflict.jobID) else { return .init(.cancel) }
        return await withCheckedContinuation { continuation in
            conflicts[conflict.jobID] = (conflict.id, continuation)
            jobs[index].pendingConflict = conflict; jobs[index].state = .awaitingConflict; publish()
        }
    }
    private func handle(_ event: OperationEvent, jobID: UUID) {
        guard let index = index(jobID), !jobs[index].state.isTerminal else { return }
        switch event {
        case .state(let state):
            // The executor's result is authoritative for terminal states. Late progress cannot resurrect it.
            if !state.isTerminal && jobs[index].pendingConflict == nil && jobs[index].state != .cancelRequested { jobs[index].state = state }
        case .progress(let value): jobs[index].progress = value
        case .item(let value):
            if !jobs[index].outcomes.contains(where: { $0.id == value.id }) { jobs[index].outcomes.append(value) }
        }
        publish()
    }
    private func setState(_ id: UUID, _ state: JobState) { if let index = index(id) { jobs[index].state = state }; publish() }
    private func index(_ id: UUID) -> Int? { jobs.firstIndex { $0.id == id } }
    private func publish() { for observer in observers.values { observer.yield(jobs) } }
    private func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
}
