import Foundation
import Darwin

final class OwnedStalledTCPPeer: @unchecked Sendable {
    private let lock = NSLock(); private var listener: Int32; private var client: Int32?
    let port: Int
    var accepted: Bool { lock.withLock { client != nil } }
    init() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0); listener = descriptor
        guard listener >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET); address.sin_addr.s_addr = inet_addr("127.0.0.1")
        guard withUnsafePointer(to: &address, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }) == 0, listen(descriptor, 1) == 0 else { Darwin.close(listener); throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) } }; port = Int(UInt16(bigEndian: address.sin_port))
        let fd = listener
        DispatchQueue.global().async { [self] in
            let accepted = Darwin.accept(fd, nil, nil)
            lock.withLock { if listener >= 0 && accepted >= 0 { client = accepted } else if accepted >= 0 { Darwin.close(accepted) } }
        }
    }
    func close() { lock.withLock { if listener >= 0 { _ = shutdown(listener, SHUT_RDWR); Darwin.close(listener); listener = -1 }; if let client { _ = shutdown(client, SHUT_RDWR); Darwin.close(client); self.client = nil } } }
    deinit { close() }
}
