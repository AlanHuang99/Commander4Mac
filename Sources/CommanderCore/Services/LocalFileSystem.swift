import Foundation
import Darwin

public struct LocalFileSystem: DirectoryProviding {
    public init() {}
    public func list(_ location: FileLocation, options: ListingOptions = .init()) async throws -> DirectorySnapshot {
        try await BlockingFileWorker.run {
            do {
                let urls = try FileManager.default.contentsOfDirectory(at: location.url, includingPropertiesForKeys: nil,
                    options: options.includeHidden ? [] : [.skipsHiddenFiles])
                let entries = try urls.map { url -> FileEntry in
                    var info = stat()
                    guard lstat(url.path, &info) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                    let type = info.st_mode & S_IFMT
                    let package = type == S_IFDIR && (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
                    let kind: FileKind = type == S_IFLNK ? .symbolicLink : (package ? .package : (type == S_IFDIR ? .directory : .file))
                    // stat exposes data-less placeholders without asking each provider for content metadata.
                    let placeholder: PlaceholderState = info.st_flags & UInt32(SF_DATALESS) != 0 ? .notDownloaded : .local
                    return FileEntry(location: .local(url), name: url.lastPathComponent, kind: kind,
                        fileIdentity: .init(device: Int64(info.st_dev), inode: info.st_ino),
                        byteSize: kind == .directory ? nil : info.st_size,
                        modificationDate: Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9),
                        placeholderState: placeholder)
                }
                return DirectorySnapshot(location: location, entries: entries)
            } catch { throw FileFailure(error, at: location) }
        }
    }
}
