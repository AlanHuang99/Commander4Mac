import Foundation
import Darwin

public protocol FileCopying: Sendable {
    func copy(source: URL, stagingDestination: URL, cancellation: OperationCancellation,
              progress: @escaping @Sendable (CopyProgress) -> Void) throws
}
public struct LocalCopyEngine: FileCopying {
    public init() {}
    public func copy(source: URL, stagingDestination: URL, cancellation: OperationCancellation,
                     progress: @escaping @Sendable (CopyProgress) -> Void) throws {
        try cancellation.check()
        guard let state = copyfile_state_alloc() else { throw POSIXError(.ENOMEM) }
        defer { copyfile_state_free(state) }
        let context = CopyContext(cancellation: cancellation, progress: progress)
        let callback: copyfile_callback_t = { what, stage, state, _, _, opaque in
            guard let opaque else { return Int32(COPYFILE_QUIT) }
            let context = Unmanaged<CopyContext>.fromOpaque(opaque).takeUnretainedValue()
            if context.cancellation.isRequested { return Int32(COPYFILE_QUIT) }
            if stage == Int32(COPYFILE_ERR) { return Int32(COPYFILE_QUIT) }
            if what == Int32(COPYFILE_COPY_DATA), let state {
                var copied: off_t = 0
                if copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied) == 0 {
                    context.report(copied: Int64(copied), finished: stage == Int32(COPYFILE_FINISH))
                }
            }
            return context.cancellation.isRequested ? Int32(COPYFILE_QUIT) : Int32(COPYFILE_CONTINUE)
        }
        guard copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self)) == 0,
              copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), Unmanaged.passUnretained(context).toOpaque()) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW | COPYFILE_EXCL)
        let status = withExtendedLifetime(context) { copyfile(source.path, stagingDestination.path, state, flags) }
        let copyError = errno
        if cancellation.isRequested { throw CancellationError() }
        if status != 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(copyError)) }
    }
}
private final class CopyContext {
    let cancellation: OperationCancellation
    private let progress: @Sendable (CopyProgress) -> Void
    private var completedBytes: Int64 = 0
    private var files = 0
    private var lastReport: UInt64 = 0
    init(cancellation: OperationCancellation, progress: @escaping @Sendable (CopyProgress) -> Void) {
        self.cancellation = cancellation; self.progress = progress
    }
    func report(copied: Int64, finished: Bool) {
        let now = DispatchTime.now().uptimeNanoseconds
        let total = completedBytes + copied
        if finished { completedBytes = total; files += 1 }
        if finished || now - lastReport > 80_000_000 {
            lastReport = now; progress(.init(bytesCopied: total, completedItems: files))
        }
    }
}
