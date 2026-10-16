import Foundation
import Darwin
import UniformTypeIdentifiers

public struct TransferTreeManifest: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let relativePath: RemotePath
        public let kind: FileKind
        public let size: UInt64?
        let revision: Revision
    }
    enum Revision: Sendable, Equatable { case local(ItemVersion), remote(RemoteFileMetadata) }
    public let source: FileLocation
    public let entries: [Entry]
    public var isDirectory: Bool { entries.first?.kind == .directory }
    func location(_ entry: Entry, under root: FileLocation) throws -> FileLocation {
        try entry.relativePath.rawValue.split(separator: "/").reduce(root) { try $0.appending(String($1)) }
    }
    func hasSameStructure(as other: Self) -> Bool {
        guard entries.count == other.entries.count else { return false }
        return zip(entries, other.entries).allSatisfy { $0.relativePath == $1.relativePath && $0.kind == $1.kind && $0.size == $1.size }
    }
}

public struct TransferTreePlanner: Sendable {
    private let remote: any RemoteFileAccess
    private let maxEntries: Int; private let maxDepth: Int
    public init(remote: any RemoteFileAccess, maxEntries: Int = 100_000, maxDepth: Int = 128) { self.remote = remote; self.maxEntries = maxEntries; self.maxDepth = maxDepth }
    public func plan(_ source: FileLocation) async throws -> TransferTreeManifest {
        var entries: [TransferTreeManifest.Entry] = []
        try await scan(source, relative: try RemotePath("/"), depth: 0, entries: &entries)
        return .init(source: source, entries: entries.sorted { $0.relativePath.rawValue.utf8.lexicographicallyPrecedes($1.relativePath.rawValue.utf8) })
    }
    private func node(_ location: FileLocation, relative: RemotePath) async throws -> TransferTreeManifest.Entry {
        try Task.checkCancellation()
        if location.isLocal {
            return try await BlockingFileWorker.run {
                let version = try ItemVersion.read(at: location.url)
                let type = version.mode & UInt16(S_IFMT)
                guard type == UInt16(S_IFDIR) || type == UInt16(S_IFREG), version.size >= 0 else { throw Self.unsupported() }
                if type == UInt16(S_IFDIR), (try location.url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true { throw Self.unsupported() }
                var info = stat(); guard lstat(location.url.path, &info) == 0, info.st_flags & UInt32(SF_DATALESS) == 0 else { throw Self.unsupported() }
                return .init(relativePath: relative, kind: version.isDirectory ? .directory : .file, size: version.isDirectory ? nil : UInt64(version.size), revision: .local(version))
            }
        }
        guard let metadata = try await remote.metadata(location) else { throw FileOperationError.message("A remote source disappeared during preflight.") }
        if metadata.kind == .directory {
            let ext = (location.title as NSString).pathExtension
            guard UTType(filenameExtension: ext)?.conforms(to: .package) != true else { throw Self.unsupported() }
        } else { guard metadata.isRegularFile, let size = metadata.size, size <= UInt64(Int64.max), metadata.modified != nil || metadata.revision != nil else { throw Self.unsupported() } }
        return .init(relativePath: relative, kind: metadata.kind, size: metadata.kind == .directory ? nil : metadata.size, revision: .remote(metadata))
    }
    private func scan(_ location: FileLocation, relative: RemotePath, depth: Int, entries: inout [TransferTreeManifest.Entry]) async throws {
        guard depth <= maxDepth, entries.count < maxEntries else { throw FileOperationError.message("The tree exceeds the transfer limit of \(maxEntries) entries or \(maxDepth) levels.") }
        let before = try await node(location, relative: relative); entries.append(before)
        guard before.kind == .directory else { return }
        let listing: DirectorySnapshot
        if location.isLocal { listing = try await LocalFileSystem().list(location, options: .init(includeHidden: true), limit: maxEntries - entries.count) }
        else { listing = try await remote.list(location, options: .init(includeHidden: true), limit: maxEntries - entries.count) }
        var names = Set<Data>()
        for entry in listing.entries.sorted(by: { $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }) {
            try Task.checkCancellation(); _ = try FileNameRules.validateComponent(entry.name)
            guard names.insert(Data(entry.name.utf8)).inserted, entry.location == (try location.appending(entry.name)), entry.kind != .symbolicLink, entry.kind != .package, entry.placeholderState != .notDownloaded else { throw Self.unsupported() }
            try await scan(entry.location, relative: relative.appending(entry.name), depth: depth + 1, entries: &entries)
        }
        guard try await node(location, relative: relative) == before else { throw FileOperationError.message("The source folder changed during preflight.") }
    }
    public func validateLocalNames(_ manifest: TransferTreeManifest, destinationDirectory: FileLocation) async throws {
        guard destinationDirectory.isLocal else { return }
        let caseSensitive = try await BlockingFileWorker.run { try destinationDirectory.url.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames ?? false }
        var names = Set<String>()
        for entry in manifest.entries where entry.relativePath.rawValue != "/" {
            var value = entry.relativePath.rawValue.precomposedStringWithCanonicalMapping
            if !caseSensitive { value = value.lowercased(with: Locale(identifier: "en_US_POSIX")) }
            guard names.insert(value).inserted else { throw FileOperationError.message("Two source names identify the same local destination. Rename them before copying this tree.") }
        }
    }
    private static func unsupported() -> FileOperationError { .message("Remote copies support regular files and folders. Packages, symlinks, special files, and files that are not downloaded are not supported.") }
}
