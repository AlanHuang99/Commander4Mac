// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation
import Observation

/// Window availability and a waiting conflict both affect presentation.
@MainActor @Observable public final class ConflictPresentationRouter {
    private var windows: [UUID] = []
    private var pending = false
    private var owner: UUID?
    public init() {}
    public var presenter: UUID? {
        guard pending else { return nil }
        if let owner, windows.contains(owner) { return owner }
        return windows.first
    }
    public func register(_ id: UUID) { if !windows.contains(id) { windows.append(id) } }
    public func unregister(_ id: UUID) { windows.removeAll { $0 == id } }
    public func setPending(owner: UUID?) { self.owner = owner; pending = true }
    public func clearPending() { pending = false; owner = nil }
}
