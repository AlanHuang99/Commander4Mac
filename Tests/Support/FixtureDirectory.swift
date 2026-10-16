import Foundation

final class FixtureDirectory {
    let url: URL
    private let marker = UUID().uuidString
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("Commander4MacTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: url.appendingPathComponent(".fixture-owner"))
    }
    func file(_ name: String, content: String = "fixture") throws -> URL {
        let target = url.appendingPathComponent(name)
        try Data(content.utf8).write(to: target)
        return target
    }
    func directory(_ name: String) throws -> URL {
        let target = url.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }
    deinit {
        if (try? String(contentsOf: url.appendingPathComponent(".fixture-owner"), encoding: .utf8)) == marker {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
