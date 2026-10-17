// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation
import Darwin

/// Owned disk backing bounds memory for both metadata and file responses.
final class DAVSpool: @unchecked Sendable {
    let directory: URL; let file: URL; let identity: FileIdentity
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Commander4Mac-WebDAV-" + UUID().uuidString)
        guard mkdir(directory.path, 0o700) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        identity = try ItemVersion.read(at: directory).identity
        file = directory.appendingPathComponent("payload")
        let fd = open(file.path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { try? FileManager.default.removeItem(at: directory); throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        Darwin.close(fd)
    }
    deinit { if (try? ItemVersion.read(at: directory).identity) == identity { try? FileManager.default.removeItem(at: directory) } }
}
struct DAVHTTPResponse: Sendable { let response: HTTPURLResponse; let spool: DAVSpool }
private final class DAVTaskCancellation: @unchecked Sendable {
    private let lock = NSLock(); private var task: URLSessionTask?; private var canceled = false
    func install(_ task: URLSessionTask) { lock.lock(); self.task = task; let cancel = canceled; lock.unlock(); task.resume(); if cancel { task.cancel() } }
    func cancel() { lock.lock(); canceled = true; let value = task; lock.unlock(); value?.cancel() }
}
final class WebDAVHTTPTransport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private final class Record {
        let continuation: CheckedContinuation<DAVHTTPResponse, any Error>; let spool: DAVSpool; let handle: FileHandle; let limit: UInt64
        var response: HTTPURLResponse?; var bytes: UInt64 = 0; var failure: (any Error)?
        init(_ continuation: CheckedContinuation<DAVHTTPResponse, any Error>, spool: DAVSpool, limit: UInt64) throws {
            self.continuation = continuation; self.spool = spool; self.limit = limit; handle = try FileHandle(forWritingTo: spool.file)
        }
    }
    private let profile: ConnectionProfile; private let secret: String
    private let lock = NSLock(); private var records: [Int: Record] = [:]; private var closed = false
    private var session: URLSession!
    init(profile: ConnectionProfile, secret: String) {
        self.profile = profile; self.secret = secret; super.init()
        let config = URLSessionConfiguration.ephemeral
        config.urlCredentialStorage = nil; config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData; config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 3600
        let queue = OperationQueue(); queue.name = "Commander4Mac.WebDAV"; queue.maxConcurrentOperationCount = 1; queue.qualityOfService = .userInitiated
        session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }
    func close() { lock.lock(); closed = true; lock.unlock(); session.invalidateAndCancel() }
    func send(_ request: URLRequest, upload: URL? = nil, limit: UInt64 = 8_388_608) async throws -> DAVHTTPResponse {
        try Task.checkCancellation()
        let box = DAVTaskCancellation()
        return try await withTaskCancellationHandler {
            let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DAVHTTPResponse, any Error>) in
                do {
                    let spool = try DAVSpool(); let record = try Record(continuation, spool: spool, limit: limit)
                    lock.lock()
                    if closed { lock.unlock(); try? record.handle.close(); continuation.resume(throwing: CancellationError()); return }
                    let task = upload.map { session.uploadTask(with: request, fromFile: $0) } ?? session.dataTask(with: request)
                    records[task.taskIdentifier] = record; lock.unlock(); box.install(task)
                } catch { continuation.resume(throwing: error) }
            }
            try Task.checkCancellation(); return response
        } onCancel: { box.cancel() }
    }
    private func record(_ task: URLSessionTask) -> Record? { lock.lock(); defer { lock.unlock() }; return records[task.taskIdentifier] }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let record = record(dataTask), let http = response as? HTTPURLResponse else { completionHandler(.cancel); return }
        record.response = http
        if response.expectedContentLength >= 0 && UInt64(response.expectedContentLength) > record.limit {
            record.failure = FileOperationError.message("The WebDAV response exceeded the allowed size."); completionHandler(.cancel)
        } else { completionHandler(.allow) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let record = record(dataTask), record.failure == nil else { return }
        guard UInt64(data.count) <= record.limit - record.bytes else { record.failure = FileOperationError.message("The WebDAV response exceeded the allowed size."); dataTask.cancel(); return }
        do { try record.handle.write(contentsOf: data); record.bytes += UInt64(data.count) }
        catch { record.failure = error; dataTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lock.lock(); let record = records.removeValue(forKey: task.taskIdentifier); lock.unlock()
        guard let record else { return }
        do {
            try record.handle.synchronize(); try record.handle.close()
            if let failure = record.failure ?? error { throw failure }
            guard let response = record.response else { throw FileOperationError.message("The WebDAV server did not return an HTTP response.") }
            record.continuation.resume(returning: .init(response: response, spool: record.spool))
        } catch { try? record.handle.close(); record.continuation.resume(throwing: error) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust { completionHandler(.performDefaultHandling, nil); return }
        guard profile.authentication != .guest, challenge.previousFailureCount == 0, !space.isProxy(), space.host.lowercased() == profile.host.lowercased(), space.port == profile.port, space.protocol?.lowercased() == (profile.secure ? "https" : "http"), [NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest].contains(space.authenticationMethod) else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        completionHandler(.useCredential, URLCredential(user: profile.username, password: secret, persistence: .none))
    }
}
