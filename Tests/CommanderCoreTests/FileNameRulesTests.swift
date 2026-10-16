import XCTest
import CommanderCore

final class FileNameRulesTests: XCTestCase {
    func testKeepBothPreservesExtensionAndDotfileName() {
        XCTAssertEqual(FileNameRules.keepBothCandidate(originalName: "report.pdf", ordinal: 1), "report copy.pdf")
        XCTAssertEqual(FileNameRules.keepBothCandidate(originalName: "report.pdf", ordinal: 2), "report copy 2.pdf")
        XCTAssertEqual(FileNameRules.keepBothCandidate(originalName: ".gitignore", ordinal: 1), ".gitignore copy")
    }
    func testNameValidationTreatsShellTextLiterallyButRejectsPathComponents() throws {
        XCTAssertEqual(try FileNameRules.validateComponent("资料 $HOME `literal`.txt"), "资料 $HOME `literal`.txt")
        for name in ["", ".", "..", "a/b", "bad\0name"] { XCTAssertThrowsError(try FileNameRules.validateComponent(name)) }
    }
}
