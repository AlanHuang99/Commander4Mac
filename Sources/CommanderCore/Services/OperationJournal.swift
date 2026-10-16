import Foundation

public enum JournalPhase: String, Codable, Sendable { case planned, copying, prepared, committing, destinationReady, complete, failed, recoveryRequired }
public struct JournalRecord: Identifiable, Codable, Sendable {
    public var id: UUID { itemID }
    public let jobID: UUID
    public let itemID: UUID
    public let source: FileLocation
    public var destination: URL
    public var staging: URL?
    public var phase: JournalPhase
    public var detail: String?
    public init(jobID: UUID, itemID: UUID, source: FileLocation, destination: URL, staging: URL?, phase: JournalPhase, detail: String? = nil) {
        self.jobID = jobID; self.itemID = itemID; self.source = source; self.destination = destination
        self.staging = staging; self.phase = phase; self.detail = detail
    }
}
public struct OperationJournal: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func record(_ record: JournalRecord) throws {
        let target = directory.appendingPathComponent(record.jobID.uuidString + "-" + record.itemID.uuidString + ".json")
        try AtomicFileWriter.write(JSONEncoder().encode(record), to: target)
    }
    public func recoverableJobs() throws -> [JournalRecord] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try JSONDecoder().decode(JournalRecord.self, from: Data(contentsOf: $0)) }
            .filter { $0.phase != .complete && $0.phase != .failed }
    }
}
