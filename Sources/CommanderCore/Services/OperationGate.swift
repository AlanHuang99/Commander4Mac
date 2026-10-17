// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation

/// One application-wide mutation lane, including short rename/create/Trash actions.
public actor OperationGate {
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    public init() {}
    public func acquire() async {
        if !held { held = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    public func release() {
        if waiters.isEmpty { held = false } else { waiters.removeFirst().resume() }
    }
}
