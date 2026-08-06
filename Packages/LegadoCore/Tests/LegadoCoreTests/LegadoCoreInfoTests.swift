import XCTest
@testable import LegadoCore

final class LegadoCoreInfoTests: XCTestCase {
    func testNameIdentifiesCorePackage() {
        XCTAssertEqual(LegadoCoreInfo.name, "LegadoCore")
    }
}
