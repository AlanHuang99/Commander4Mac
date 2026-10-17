// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation
import Darwin

public enum LocalKeyMaterial {
    /// Call from a bounded filesystem worker. Never read an unbounded user-selected file.
    public static func read(_ reference: LocationReference) throws -> Data {
        guard case .available(let location) = LocationResolver().resolve(reference) else { throw FileOperationError.message("The saved private key is unavailable. Choose it again.") }
        let fd = open(location.url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw FileOperationError.message("The private key cannot be opened. Choose a regular OpenSSH Ed25519 key file.") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & UInt16(S_IFMT) == UInt16(S_IFREG), info.st_size <= 1_048_576,
              FileIdentity(device: Int64(info.st_dev), inode: info.st_ino) == reference.expectedIdentity else {
            throw FileOperationError.message("The key file changed, is not a regular file, or exceeds 1 MiB.")
        }
        let data = try handle.read(upToCount: 1_048_577) ?? Data()
        guard data.count <= 1_048_576 else { throw FileOperationError.message("The private key file is too large.") }
        return data
    }
}
