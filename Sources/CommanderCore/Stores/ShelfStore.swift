import Foundation
import Observation

@MainActor @Observable public final class ShelfStore {
    public private(set) var items: [StagedItem]
    public init(items: [StagedItem] = []) { self.items = items }
    public func stage(_ locations: [FileLocation]) async throws {
        let added = try await BlockingFileWorker.run {
            try locations.map { StagedItem(reference: try LocationResolver().reference(for: $0), displayName: $0.url.lastPathComponent) }
        }
        for item in added where !items.contains(where: { $0.reference.displayURL.standardizedFileURL.path == item.reference.displayURL.standardizedFileURL.path }) {
            items.append(item)
        }
    }
    public func remove(ids: Set<UUID>) { items.removeAll { ids.contains($0.id) } }
    public func clear() { items.removeAll() }
    public func resolvedLocations(ids: Set<UUID>? = nil) async throws -> [FileLocation] {
        let captured = items.filter { ids == nil || ids!.contains($0.id) }
        let resolved = try await BlockingFileWorker.run {
            try captured.map { item -> (UUID, FileLocation, LocationReference) in
                switch LocationResolver().resolve(item.reference) {
                case .available(let location): return (item.id, location, try LocationResolver().reference(for: location))
                case .unavailable(let message), .needsRelink(let message): throw FileOperationError.message(message)
                }
            }
        }
        // Refresh moved bookmarks before matching later outcomes to the captured shelf entries.
        for (id, _, reference) in resolved {
            if let index = items.firstIndex(where: { $0.id == id }) { items[index].reference = reference }
        }
        return resolved.map { $0.1 }
    }
    public func apply(_ result: OperationResult, capturedIDs: Set<UUID>? = nil) {
        let successful = Set(result.outcomes.filter { $0.state == .completed }.map { $0.source.url.path })
        items.removeAll { item in
            (capturedIDs == nil || capturedIDs!.contains(item.id)) && successful.contains(item.reference.displayURL.path)
        }
    }
}
