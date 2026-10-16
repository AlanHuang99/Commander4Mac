import Foundation

/// Owns the complete editor submission, including preparation before a network
/// attempt exists. Cancel never operates on an unrelated established session.
@MainActor public final class ConnectionSubmission {
    private var task: Task<Void, Never>?
    private var token: UUID?
    public init() {}
    @discardableResult public func start<Value: Sendable>(
        prepare: @escaping @MainActor () async throws -> Value,
        perform: @escaping @MainActor (Value) async throws -> Void,
        completion: @escaping @MainActor (Result<Void, any Error>) -> Void
    ) -> Task<Void, Never> {
        cancel()
        let id = UUID(); token = id
        let job = Task { [weak self] in
            do {
                try Task.checkCancellation()
                let value = try await prepare()
                try Task.checkCancellation()
                try await perform(value)
                try Task.checkCancellation()
                guard self?.token == id else { return }
                self?.token = nil; self?.task = nil; completion(.success(()))
            } catch {
                guard self?.token == id else { return }
                self?.token = nil; self?.task = nil
                if !Task.isCancelled { completion(.failure(error)) }
            }
        }
        task = job; return job
    }
    public func cancel() { token = nil; task?.cancel(); task = nil }
}
