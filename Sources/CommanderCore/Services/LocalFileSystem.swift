import Foundation
import Darwin

public struct LocalFileSystem: DirectoryProviding {
    public init() {}
    public func list(_ location: FileLocation, options: ListingOptions = .init()) async throws -> DirectorySnapshot {
        try await list(location, options: options, limit: Int.max)
    }
    public func list(_ location: FileLocation, options: ListingOptions, limit: Int) async throws -> DirectorySnapshot {
        try location.requireLocal(); try Task.checkCancellation()
        guard limit >= 0 else { throw FileOperationError.message("Directory entry limit must be nonnegative.") }
        let cancellation = OperationCancellation()
        return try await withTaskCancellationHandler {
            try await BlockingFileWorker.run {
                try cancellation.check()
                do {
                    guard let directory = opendir(location.url.path) else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                    defer { closedir(directory) }
                    var entries: [FileEntry] = []
                    while true {
                        try cancellation.check(); errno = 0
                        guard let item = readdir(directory) else { if errno != 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }; break }
                        let name = withUnsafePointer(to: &item.pointee.d_name) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(validatingCString: $0) } }
                        guard let name else { throw FileOperationError.message("A filename is not valid UTF-8.") }
                        if name == "." || name == ".." || (!options.includeHidden && name.hasPrefix(".")) { continue }
                        let url = location.url.appendingPathComponent(name)
                        var info = stat(); guard lstat(url.path, &info) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                        if !options.includeHidden && info.st_flags & UInt32(UF_HIDDEN) != 0 { continue }
                        guard entries.count < limit else { throw FileOperationError.message("Directory entry limit exceeded.") }
                        let type = info.st_mode & S_IFMT
                        let package = type == S_IFDIR && (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
                        let kind: FileKind = type == S_IFLNK ? .symbolicLink : (package ? .package : (type == S_IFDIR ? .directory : .file))
                        let placeholder: PlaceholderState = info.st_flags & UInt32(SF_DATALESS) != 0 ? .notDownloaded : .local
                        entries.append(.init(location: .local(url), name: name, kind: kind, fileIdentity: .init(device: Int64(info.st_dev), inode: info.st_ino), byteSize: kind == .directory ? nil : info.st_size, modificationDate: Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9), placeholderState: placeholder))
                    }
                    try cancellation.check(); return .init(location: location, entries: entries)
                } catch is CancellationError { throw CancellationError() }
                catch { throw FileFailure(error, at: location) }
            }
        } onCancel: { cancellation.cancel() }
    }
}
