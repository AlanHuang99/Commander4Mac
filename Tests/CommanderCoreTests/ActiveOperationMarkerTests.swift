import XCTest
import CommanderCore

final class ActiveOperationMarkerTests: XCTestCase {
    func testMarkerCarriesProcessIdentityAndClearsAtIdle() throws {
        let f = try FixtureDirectory(); let marker = ActiveOperationMarker(directory: f.url)
        try marker.publish(pid: 123, executablePath: "/Applications/Test.app/Contents/MacOS/Test", executableUUID: "fixture-uuid", activeJobs: 2)
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: marker.fileURL)) as? [String: Any])
        XCTAssertEqual(value["pid"] as? Int, 123)
        XCTAssertEqual(value["executableUUID"] as? String, "fixture-uuid")
        XCTAssertEqual(value["activeJobs"] as? Int, 2)
        try marker.publish(pid: 123, executablePath: "", executableUUID: "", activeJobs: 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.fileURL.path))
    }
}
