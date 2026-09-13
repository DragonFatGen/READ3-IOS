import XCTest
@testable import LegadoIOS

final class ReaderScrollMetricsTests: XCTestCase {
    func testSavedProgressRestoresAgainstScrollableExtent() {
        let metrics = ReaderScrollMetrics(offset: 400, contentHeight: 1200, viewportHeight: 400)
        XCTAssertEqual(metrics.progress, 0.5)
        XCTAssertEqual(metrics.offset(forProgress: metrics.progress), 400)
        XCTAssertEqual(metrics.offset(forProgress: 1), 800)
    }

    func testShortContentAndOutOfRangeProgressAreClamped() {
        let short = ReaderScrollMetrics(offset: 0, contentHeight: 200, viewportHeight: 400)
        XCTAssertEqual(short.offset(forProgress: 0.5), 0)
        let long = ReaderScrollMetrics(offset: 0, contentHeight: 1200, viewportHeight: 400)
        XCTAssertEqual(long.offset(forProgress: -1), 0)
        XCTAssertEqual(long.offset(forProgress: 2), 800)
    }
}
