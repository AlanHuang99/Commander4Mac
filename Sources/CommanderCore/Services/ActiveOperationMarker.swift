// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation

public struct ActiveOperationMarker: Sendable {
    public let fileURL: URL
    public init(directory: URL) { fileURL = directory.appendingPathComponent("active-operation.json") }
    public func publish(pid: Int32, executablePath: String, executableUUID: String, activeJobs: Int) throws {
        if activeJobs == 0 {
            if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
        } else {
            let record = Record(pid: pid, executablePath: executablePath, executableUUID: executableUUID, activeJobs: activeJobs)
            try AtomicFileWriter.write(JSONEncoder().encode(record), to: fileURL)
        }
    }
    private struct Record: Codable {
        let pid: Int32
        let executablePath: String
        let executableUUID: String
        let activeJobs: Int
    }
}
