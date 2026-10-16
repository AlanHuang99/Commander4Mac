import Foundation
import Dispatch
import Darwin

public struct DirectoryWatcher: Sendable {
    public init() {}
    public func events(for location: FileLocation) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let handle = WatchHandle()
            continuation.onTermination = { _ in handle.cancel() }
            DispatchQueue.global(qos: .utility).async {
                let descriptor = open(location.url.path, O_EVTONLY)
                guard descriptor >= 0 else { continuation.finish(); return }
                let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                    eventMask: [.write, .delete, .rename, .attrib, .extend], queue: .global(qos: .utility))
                source.setEventHandler { continuation.yield(()) }
                source.setCancelHandler { close(descriptor) }
                handle.install(source); source.resume()
            }
        }
    }
}
private final class WatchHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var source: (any DispatchSourceFileSystemObject)?
    private var canceled = false
    func install(_ source: any DispatchSourceFileSystemObject) {
        lock.lock(); defer { lock.unlock() }
        if canceled { source.cancel() } else { self.source = source }
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        canceled = true; source?.cancel(); source = nil
    }
}
