import LegadoCore
import Foundation
import XCTest
@testable import LegadoIOS

final class BookUpdateCheckerTests: XCTestCase {
    func testFirstCheckBuildsBaselineWithoutUpdates() async throws {
        let checker = TOCBookUpdateChecker(tocService: UpdateTOCService(chapters: chapters(through: 100)))
        let result = try await checker.checkUpdate(for: book(), source: testSource())
        XCTAssertEqual(result.chapterCount, 100)
        XCTAssertEqual(result.newChapterCount, 0)
    }

    func testLatestURLCalculatesChaptersAfterMatchAndAvoidsDuplicates() {
        var value = book()
        value.lastKnownChapterCount = 100
        value.lastKnownLatestChapterURL = "chapter-100"
        var values = chapters(through: 105)
        values.insert(values[99], at: 50)
        values.append(values[101])
        XCTAssertEqual(TOCBookUpdateChecker.newChapterCount(for: value, chapters: values), 5)
    }

    func testMissingLatestURLFallsBackToPositiveCountDifference() {
        var value = book()
        value.lastKnownChapterCount = 100
        value.lastKnownLatestChapterURL = "old-missing-url"
        XCTAssertEqual(TOCBookUpdateChecker.newChapterCount(for: value, chapters: chapters(through: 105)), 5)
        XCTAssertEqual(TOCBookUpdateChecker.newChapterCount(for: value, chapters: chapters(through: 90)), 0)
    }

    func testEmptyTOCIsRejected() async {
        let checker = TOCBookUpdateChecker(tocService: UpdateTOCService(chapters: []))
        do {
            _ = try await checker.checkUpdate(for: book(), source: testSource())
            XCTFail("Expected empty TOC error")
        } catch let error as BookUpdateCheckError {
            XCTAssertEqual(error, .emptyTableOfContents)
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    private func book() -> LibraryBook { LibraryBook(source: testSource(), bookInfo: testBookInfo()) }
}

private struct UpdateTOCService: TOCLoading {
    let chapters: [BookChapterResult]
    func loadTOC(source: BookSource, book: BookInfoResult) async throws -> [BookChapterResult] { chapters }
}

private func chapters(through count: Int) -> [BookChapterResult] {
    guard count > 0 else { return [] }
    return (1...count).map { number in
        BookChapterResult(
            name: "第 \(number) 章", url: "chapter-\(number)", isVolume: false,
            index: number - 1, bookURL: "book", sourceURL: "source"
        )
    }
}
