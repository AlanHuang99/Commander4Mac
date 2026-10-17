// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation
import Observation

@MainActor @Observable
public final class FavoriteStore {
    public var items: [Favorite]
    public init(items: [Favorite] = []) { self.items = items }
    public func add(name: String, location: FileLocation, destination: OpenDestination? = nil) async throws {
        let reference = try await BlockingFileWorker.run { try LocationResolver().reference(for: location) }
        items.append(.init(id: UUID(), name: name, reference: reference, destination: destination))
    }
    public func rename(id: UUID, to name: String) {
        guard let index = items.firstIndex(where: { $0.id == id }), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        items[index].name = name
    }
    public func move(id: UUID, to index: Int) {
        guard let old = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: old); items.insert(item, at: min(max(0,index),items.count))
    }
    public func remove(id: UUID) { items.removeAll { $0.id == id } }
}
