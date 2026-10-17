// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation

public final class OperationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var requested = false
    private var observers: [UUID: @Sendable () -> Void] = [:]
    public init() {}
    public var isRequested: Bool { lock.lock(); defer { lock.unlock() }; return requested }
    public func cancel() {
        let callbacks: [@Sendable () -> Void] = lock.withLock {
            guard !requested else { return [] }
            requested = true; let callbacks = Array(observers.values); observers.removeAll(); return callbacks
        }
        for callback in callbacks { callback() }
    }
    public func observe(_ callback: @escaping @Sendable () -> Void) -> UUID {
        let id = UUID()
        let immediate = lock.withLock { if requested { return true }; observers[id] = callback; return false }
        if immediate { callback() }; return id
    }
    public func removeObserver(_ id: UUID) { _ = lock.withLock { observers.removeValue(forKey: id) } }
    public func check() throws { if isRequested { throw CancellationError() } }
}
