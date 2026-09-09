import XCTest
@testable import LegadoCore

final class CompatibilityDiagnosticTests: XCTestCase {
    func testRedactsMultipartAndQuotedSensitiveValues() {
        let input = "Authorization: Bearer private-auth\nCookie: a=private-a; b=private-b\n"
            + "\"password\": \"private-password\"\nloginParams=private-login\nvariables=private-vars"
        let output = BookSourceCompatibilityRunner.redacted(input)
        XCTAssertFalse(output.contains("private-"))
        XCTAssertTrue(output.contains("<redacted>"))
    }

    func testDiagnosticLengthRemainsBounded() {
        XCTAssertEqual(BookSourceCompatibilityRunner.redacted(String(repeating: "字", count: 600)).count, 500)
    }
}
