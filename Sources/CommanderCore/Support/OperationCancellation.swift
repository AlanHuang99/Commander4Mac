import Foundation

public final class OperationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var requested = false
    public init() {}
    public var isRequested: Bool { lock.lock(); defer { lock.unlock() }; return requested }
    public func cancel() { lock.lock(); requested = true; lock.unlock() }
    public func check() throws { if isRequested { throw CancellationError() } }
}
