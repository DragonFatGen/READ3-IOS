import XCTest
@testable import LegadoCore

final class HistoricalSelectorIndexTests: XCTestCase {
    func testSinglePositiveIndex() {
        XCTAssertEqual(HistoricalSelectorIndex.parse("li[1]").indexes(for: 5), [1])
    }

    func testNegativeIndex() {
        XCTAssertEqual(HistoricalSelectorIndex.parse("li[-1]").indexes(for: 5), [4])
    }

    func testInclusiveRange() {
        XCTAssertEqual(HistoricalSelectorIndex.parse("li[0:3]").indexes(for: 5), [0, 1, 2, 3])
    }

    func testMultipleIndexesPreserveRuleOrderAndRemoveDuplicates() {
        XCTAssertEqual(HistoricalSelectorIndex.parse("li[4,0,2,0]").indexes(for: 5), [4, 0, 2])
    }

    func testReverseRange() {
        XCTAssertEqual(HistoricalSelectorIndex.parse("li[-1:0]").indexes(for: 5), [4, 3, 2, 1, 0])
    }

    func testOpenRangeAndStep() {
        XCTAssertEqual(HistoricalSelectorIndex.parse("li[:4:2]").indexes(for: 6), [0, 2, 4])
    }

    func testOutOfBoundsIndexesAreIgnoredButRangeBoundsClamp() {
        XCTAssertEqual(HistoricalSelectorIndex.parse("li[99,-99]").indexes(for: 5), [])
        XCTAssertEqual(HistoricalSelectorIndex.parse("li[2:99]").indexes(for: 5), [2, 3, 4])
    }

    func testLegacyDotAndBangIndexSyntax() {
        let included = HistoricalSelectorIndex.parse("tag.li.0:2:-1")
        XCTAssertEqual(included.selector, "tag.li")
        XCTAssertEqual(included.mode, .include)
        XCTAssertEqual(included.indexes(for: 5), [0, 2, 4])

        let excluded = HistoricalSelectorIndex.parse("tag.li!1:3")
        XCTAssertEqual(excluded.mode, .exclude)
        XCTAssertEqual(excluded.indexes(for: 5), [1, 3])
    }
}
