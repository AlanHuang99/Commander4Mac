import Foundation
import MachO

struct RuntimeIdentity {
    static var bundleIdentifier: String { Bundle.main.bundleIdentifier ?? "unknown" }
    static var bundleURL: URL { Bundle.main.bundleURL }
    static var executableURL: URL? { Bundle.main.executableURL }
    static var executableUUID: String {
        guard let header = _dyld_get_image_header(0), header.pointee.magic == MH_MAGIC_64 else { return "unavailable" }
        var cursor = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
        for _ in 0..<header.pointee.ncmds {
            let command = cursor.load(as: load_command.self)
            guard command.cmdsize >= MemoryLayout<load_command>.size else { break }
            if command.cmd == LC_UUID {
                let uuid = cursor.load(as: uuid_command.self).uuid
                return withUnsafeBytes(of: uuid) { NSUUID(uuidBytes: $0.bindMemory(to: UInt8.self).baseAddress!).uuidString }
            }
            cursor = cursor.advanced(by: Int(command.cmdsize))
        }
        return "unavailable"
    }
}
