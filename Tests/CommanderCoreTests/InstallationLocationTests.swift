import XCTest
import CommanderCore

final class InstallationLocationTests: XCTestCase {
    func testOnlyInstalledApplicationLocationsSkipMoveInstructions() {
        let home = URL(fileURLWithPath: "/Users/owned", isDirectory: true)
        let cases: [(String, Bool)] = [
            ("/Applications/Commander4Mac.app", true),
            ("/Applications/Utilities/Commander4Mac.app", true),
            ("/Users/owned/Applications/Commander4Mac.app", true),
            ("/Users/owned/Downloads/Commander4Mac.app", false),
            ("/Volumes/Commander4Mac Install/Commander4Mac.app", false),
            ("/private/var/folders/owned/AppTranslocation/id/d/Commander4Mac.app", false),
            ("/Applications Backup/Commander4Mac.app", false),
            ("/Applications/../Volumes/Install/Commander4Mac.app", false)
        ]
        for (path, expected) in cases {
            XCTAssertEqual(InstallationLocation.isInstalled(URL(fileURLWithPath: path), homeDirectory: home), expected, path)
        }
        XCTAssertFalse(InstallationLocation.isInstalled(URL(string: "https://example.invalid/Applications/App.app")!, homeDirectory: home))
    }
}
