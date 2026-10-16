import Foundation

public enum RemotePathRules {
    public static func validate(_ path: RemotePath, for kind: ConnectionProtocol) throws {
        for component in path.rawValue.split(separator: "/") {
            switch kind {
            case .sftp: break
            case .smb:
                guard !component.contains("\\"), !component.contains(":") else { throw FileOperationError.message("SMB backslash and alternate-stream paths are not supported. Rename those items before copying.") }
            case .webdav:
                guard !component.contains("\\"), !component.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw FileOperationError.message("WebDAV names cannot contain backslashes or control characters. Rename those items before copying.") }
            }
        }
    }
}
