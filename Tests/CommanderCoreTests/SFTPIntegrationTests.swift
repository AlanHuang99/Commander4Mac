import XCTest
import CommanderCore

final class SFTPIntegrationTests: XCTestCase, @unchecked Sendable {
    func testRealSFTPKeyVerificationListingAndFileOperations() async throws {
        guard let fixture = ProcessInfo.processInfo.environment["COMMANDER_SFTP_FIXTURE"] else { throw XCTSkip("Owned loopback SFTP fixture required") }
        let root = URL(fileURLWithPath: fixture)
        let config = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("fixture.json"))) as! [String: Any]
        let dataRoot = root.appendingPathComponent("data/test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: false)
        try Data("SFTP fixture".utf8).write(to: dataRoot.appendingPathComponent("hello.txt"))
        defer { try? FileManager.default.removeItem(at: dataRoot) }
        var profile = ConnectionProfile(host: "127.0.0.1", port: config["port"] as! Int, username: config["username"] as! String,
                                        initialPath: dataRoot.path, authentication: .ed25519Key)
        profile.keyReference = try LocationResolver().reference(for: .local(root.appendingPathComponent("user_key")))
        let manager = SFTPConnectionManager()
        let socketsBefore = try fixtureSocketCount(port: profile.port)
        do { try await manager.connect(profile, secret: ""); XCTFail("Untrusted host must fail") }
        catch { XCTAssertTrue(error is HostKeyChallenge, "Expected host verification, got \(error)") }
        XCTAssertEqual(try fixtureSocketCount(port: profile.port), socketsBefore, "Rejected host verification must close its TCP transport")
        let verificationState = await manager.state(profile.id); XCTAssertEqual(verificationState, .verificationRequired)
        profile.serverKey = try String(contentsOf: root.appendingPathComponent("host_key.pub"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        try await manager.connect(profile, secret: "")
        let connectedState = await manager.state(profile.id); XCTAssertEqual(connectedState, .connected)
        let location = FileLocation.sftp(profileID: profile.id, path: try RemotePath(profile.initialPath))
        let listing = try await manager.list(location, options: .init())
        XCTAssertTrue(listing.entries.contains { $0.name == "hello.txt" })
        let original = try location.appending("hello.txt")
        let reader = try await manager.openFile(original, writeExclusive: false)
        let bytes = try await reader.read(offset: 0, length: 65536); try await reader.close()
        XCTAssertEqual(String(data: bytes, encoding: .utf8), "SFTP fixture")
        let uploaded = try location.appending("uploaded.txt")
        let writer = try await manager.openFile(uploaded, writeExclusive: true)
        try await writer.write(Data("uploaded fixture".utf8), offset: 0); try await writer.close()
        do { _ = try await manager.openFile(uploaded, writeExclusive: true); XCTFail("Exclusive create must refuse existing files") } catch { }
        let renamed = try location.appending("renamed.txt")
        try await manager.rename(uploaded, to: renamed)
        XCTAssertEqual(try String(contentsOf: dataRoot.appendingPathComponent("renamed.txt"), encoding: .utf8), "uploaded fixture")
        try await manager.createDirectory(try location.appending("new-folder"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dataRoot.appendingPathComponent("new-folder").path))
        do { _ = try await manager.list(try location.appending("missing"), options: .init()); XCTFail("Missing directory is not empty success") } catch { }
        let denied = dataRoot.appendingPathComponent("denied")
        try FileManager.default.createDirectory(at: denied, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: denied.path) }
        do { _ = try await manager.list(try location.appending("denied"), options: .init()); XCTFail("Denied directory is not empty success") }
        catch { XCTAssertTrue(error.localizedDescription.lowercased().contains("denied"), error.localizedDescription) }
        do { try await manager.rename(renamed, to: original); XCTFail("Rename must not overwrite an existing item") } catch { }
        XCTAssertEqual(try String(contentsOf: dataRoot.appendingPathComponent("hello.txt"), encoding: .utf8), "SFTP fixture")
        let local = try FixtureDirectory(); let source = try local.file("round trip #中文.bin", content: String(repeating: "SFTP bytes", count: 20_000))
        let localDestination = try local.directory("download")
        let executor = RemoteTransferExecutor(remote: manager, journal: .init(directory: local.url.appendingPathComponent("journal")))
        let up = await executor.executeRequest(.init(kind: .copy, sources: [.local(source)], destinationDirectory: location), cancellation: .init(), resolveConflict: { _ in .init(.skip) }, emit: { _ in })
        XCTAssertEqual(up.state, .completed, up.outcomes.first?.detail ?? "")
        let down = await executor.executeRequest(.init(kind: .copy, sources: [try location.appending(source.lastPathComponent)], destinationDirectory: .local(localDestination)), cancellation: .init(), resolveConflict: { _ in .init(.skip) }, emit: { _ in })
        XCTAssertEqual(down.state, .completed, down.outcomes.first?.detail ?? "")
        XCTAssertEqual(try Data(contentsOf: source), try Data(contentsOf: localDestination.appendingPathComponent(source.lastPathComponent)))
        await manager.disconnect(profile.id)
        let disconnectedState = await manager.state(profile.id); XCTAssertEqual(disconnectedState, .disconnected)
        do { _ = try await manager.list(location, options: .init()); XCTFail("Disconnected listing must fail") } catch { }
        profile.serverKey = "ssh-ed25519 Y2hhbmdlZA=="
        let restoredManager = SFTPConnectionManager()
        do { try await restoredManager.connect(profile, secret: ""); XCTFail("Changed key must fail") }
        catch { XCTAssertNotNil((error as? HostKeyChallenge)?.previousFingerprint) }
    }
    private func fixtureSocketCount(port: Int) throws -> Int {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-a", "-p", String(ProcessInfo.processInfo.processIdentifier), "-iTCP:\(port)"]
        let output = Pipe(); process.standardOutput = output; process.standardError = Pipe()
        try process.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        return max(0, String(decoding: data, as: UTF8.self).split(separator: "\n").count - 1)
    }

}
