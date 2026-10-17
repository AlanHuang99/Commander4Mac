// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation
import Observation

/// Keeps updater callbacks on the same actor as operation admission and workspace capture.
@MainActor @Observable public final class UpdateRelaunchCoordinator {
    public enum Phase: Sendable { case idle, waitingForOperations, savingWorkspace, saveFailed, installing }
    public private(set) var phase: Phase = .idle
    public var blocksNewOperations: Bool { phase == .savingWorkspace || phase == .installing }
    @ObservationIgnored private var activeCount = 0
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var flush: (@MainActor () async -> Bool)?
    @ObservationIgnored private var install: (@MainActor () -> Void)?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    public init() {}

    public func postponeRelaunch(activeOperationCount: Int, flush: @escaping @MainActor () async -> Bool,
                                 install: @escaping @MainActor () -> Void) {
        guard self.install == nil, phase != .installing else { return }
        self.flush = flush; self.install = install; activeCount = max(0, activeOperationCount)
        phase = .waitingForOperations; saveIfDrained()
    }
    public func updateActiveOperationCount(_ count: Int) {
        activeCount = max(0, count)
        // Defensive invalidation also covers work already admitted just before the save.
        if activeCount > 0, phase == .savingWorkspace {
            generation &+= 1; saveTask?.cancel(); saveTask = nil; phase = .waitingForOperations
        }
        if phase == .waitingForOperations { saveIfDrained() }
    }
    public func retryStateSave() {
        guard phase == .saveFailed else { return }
        phase = .waitingForOperations; saveIfDrained()
    }
    public func cancel() {
        generation &+= 1; saveTask?.cancel(); saveTask = nil
        install = nil; flush = nil; phase = .idle
    }
    private func saveIfDrained() {
        guard activeCount == 0, phase == .waitingForOperations, let flush, install != nil else { return }
        phase = .savingWorkspace; generation &+= 1
        let revision = generation
        saveTask = Task { [weak self] in
            let saved = await flush()
            guard !Task.isCancelled, let self, self.generation == revision, self.activeCount == 0 else { return }
            self.saveTask = nil
            guard saved else { self.phase = .saveFailed; return }
            let callback = self.install
            self.install = nil; self.flush = nil; self.phase = .installing
            callback?()
        }
    }
}
