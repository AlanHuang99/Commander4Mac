// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation
import Observation

@MainActor @Observable public final class ShelfStore {
    public private(set) var unavailable: [UUID: String] = [:]
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
            captured.map { item -> ShelfResolution in
                do {
                    switch LocationResolver().resolve(item.reference) {
                    case .available(let location): return .init(id: item.id, location: location, reference: try LocationResolver().reference(for: location), problem: nil)
                    case .unavailable(let message), .needsRelink(let message): return .init(id: item.id, location: nil, reference: nil, problem: message)
                    }
                } catch { return .init(id: item.id, location: nil, reference: nil, problem: error.localizedDescription) }
            }
        }
        for result in resolved {
            unavailable[result.id] = result.problem
            if let reference = result.reference, let index = items.firstIndex(where: { $0.id == result.id }) { items[index].reference = reference }
        }
        let problems = resolved.compactMap(\.problem)
        guard problems.isEmpty else { throw FileOperationError.message(problems.joined(separator: "\n")) }
        return resolved.compactMap(\.location)
    }
    public func relink(id: UUID, to location: FileLocation) async throws {
        let reference = try await BlockingFileWorker.run { try LocationResolver().reference(for: location) }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index] = StagedItem(id: id, reference: reference, displayName: location.url.lastPathComponent)
        unavailable.removeValue(forKey: id)
    }
    public func apply(_ result: OperationResult, capturedIDs: Set<UUID>? = nil) {
        let successful = Set(result.outcomes.filter { $0.state == .completed }.map { $0.source.url.path })
        items.removeAll { item in
            (capturedIDs == nil || capturedIDs!.contains(item.id)) && successful.contains(item.reference.displayURL.path)
        }
    }
}

private struct ShelfResolution: Sendable {
    let id: UUID
    let location: FileLocation?
    let reference: LocationReference?
    let problem: String?
}
