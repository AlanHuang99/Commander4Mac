import Foundation

public struct ConnectionLoadResult: Sendable { public let profiles: [ConnectionProfile]; public let diagnostic: String? }
public struct ConnectionStore: Sendable {
    private struct Document: Codable { var version = 1; let profiles: [ConnectionProfile] }
    public let fileURL: URL
    public init(directory: URL) { fileURL = directory.appendingPathComponent("connections.json") }
    public func save(_ profiles: [ConnectionProfile]) throws {
        let valid = try profiles.map { try $0.validated() }
        guard Set(valid.map(\.id)).count == valid.count else { throw FileOperationError.message("Duplicate connection identifiers.") }
        try AtomicFileWriter.write(JSONEncoder().encode(Document(profiles: valid)), to: fileURL)
    }
    public func load() -> ConnectionLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .init(profiles: [], diagnostic: nil) }
        do {
            let doc = try JSONDecoder().decode(Document.self, from: Data(contentsOf: fileURL))
            guard doc.version == 1, Set(doc.profiles.map(\.id)).count == doc.profiles.count else { throw CocoaError(.coderReadCorrupt) }
            return .init(profiles: try doc.profiles.map { try $0.validated() }, diagnostic: nil)
        } catch {
            let backup = fileURL.deletingLastPathComponent().appendingPathComponent("connections-corrupt-\(UUID().uuidString).json")
            do { try FileManager.default.copyItem(at: fileURL, to: backup) }
            catch { return .init(profiles: [], diagnostic: "Could not preserve unreadable connections: \(error.localizedDescription)") }
            return .init(profiles: [], diagnostic: "Unreadable connections were preserved for recovery.")
        }
    }
}
