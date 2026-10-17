// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation
import Darwin

public struct LocalMutation: Sendable {
    public enum Kind: Sendable { case rename, createDirectory }
    public let kind: Kind
    public let before: FileLocation?
    public let after: FileLocation
    public let expectedAfter: ItemVersion
}
public protocol FileTrashing: Sendable { func trash(_ url: URL) throws -> URL? }
public struct SystemFileTrasher: FileTrashing {
    public init() {}
    public func trash(_ url: URL) throws -> URL? {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return result as URL?
    }
}
public struct LocalFileActions: Sendable {
    private let gate: OperationGate
    private let trasher: any FileTrashing
    public init(gate: OperationGate = .init(), trasher: any FileTrashing = SystemFileTrasher()) { self.gate = gate; self.trasher = trasher }
    public func rename(_ source: FileLocation, to name: String) async throws -> LocalMutation {
        try source.requireLocal()
        let name = try FileNameRules.validateComponent(name)
        return try await perform {
            let destination = source.url.deletingLastPathComponent().appendingPathComponent(name)
            guard source.url.path != destination.path else { throw FileOperationError.message("The name has not changed.") }
            let expected = try ItemVersion.read(at: source.url)
            try Self.renameExclusiveIncludingCase(source.url, destination, expected: expected)
            return .init(kind: .rename, before: source, after: .local(destination), expectedAfter: try ItemVersion.read(at: destination))
        }
    }
    public func createDirectory(named name: String, in parent: FileLocation) async throws -> LocalMutation {
        try parent.requireLocal()
        let name = try FileNameRules.validateComponent(name)
        return try await perform {
            let url = parent.url.appendingPathComponent(name)
            guard mkdir(url.path, 0o755) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            return .init(kind: .createDirectory, before: nil, after: .local(url), expectedAfter: try ItemVersion.read(at: url))
        }
    }
    public func trash(_ locations: [FileLocation]) async -> [ItemOperationOutcome] {
        do {
            return try await perform {
                locations.map { location in
                    do {
                        try location.requireLocal()
                        let destination = try trasher.trash(location.url)
                        return .init(source: location, destination: destination.map(FileLocation.local), state: .completed)
                    } catch { return .init(source: location, state: .failed, detail: FileFailure(error, at: location).detail) }
                }
            }
        } catch { return locations.map { .init(source: $0, state: .failed, detail: error.localizedDescription) } }
    }
    public func undo(_ mutation: LocalMutation) async throws {
        try await perform {
            let actual = try ItemVersion.read(at: mutation.after.url)
            switch mutation.kind {
            case .rename:
                guard actual == mutation.expectedAfter, let before = mutation.before else {
                    throw FileOperationError.message("This item changed after renaming. Undo has left it untouched.")
                }
                try Self.renameExclusiveIncludingCase(mutation.after.url, before.url, expected: actual)
            case .createDirectory:
                guard actual.identity == mutation.expectedAfter.identity, actual.isDirectory else {
                    throw FileOperationError.message("This folder was replaced. Undo has left it untouched.")
                }
                // rmdir atomically refuses a nonempty directory. No recursive delete fallback.
                guard rmdir(mutation.after.url.path) == 0 else { throw FileOperationError.message("The folder contains files or cannot be removed. Undo has left it untouched.") }
            }
        }
    }
    private func perform<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        await gate.acquire()
        do { let result = try await BlockingFileWorker.run(body); await gate.release(); return result }
        catch { await gate.release(); throw error }
    }
    private static func renameExclusiveIncludingCase(_ source: URL, _ destination: URL, expected: ItemVersion) throws {
        let backend = SystemFileOperationBackend()
        do { try backend.renameExclusive(from: source, to: destination) }
        catch {
            let ns = error as NSError
            guard ns.domain == NSPOSIXErrorDomain, ns.code == Int(EEXIST),
                  source.lastPathComponent.caseInsensitiveCompare(destination.lastPathComponent) == .orderedSame,
                  try ItemVersion.read(at: destination).identity == expected.identity,
                  !(try FileManager.default.contentsOfDirectory(atPath: source.deletingLastPathComponent().path).contains(destination.lastPathComponent)) else { throw error }
            // A case-insensitive volume can report the old directory entry as occupied.
            // Two exclusive renames avoid replacing an unrelated case-sensitive sibling.
            let temporary = source.deletingLastPathComponent().appendingPathComponent(".commander4mac-rename-" + UUID().uuidString)
            try backend.renameExclusive(from: source, to: temporary)
            do { try backend.renameExclusive(from: temporary, to: destination) }
            catch {
                do { try backend.renameExclusive(from: temporary, to: source) }
                catch { throw FileOperationError.message("The item is preserved at \(temporary.path). Restore its name after resolving the new collision.") }
                throw error
            }
        }
    }
}
