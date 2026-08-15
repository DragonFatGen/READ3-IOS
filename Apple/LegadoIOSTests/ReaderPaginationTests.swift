import XCTest
@testable import LegadoIOS

@MainActor
final class ReaderPaginationTests: XCTestCase {
    private let configuration = PaginationConfiguration(
        size: CGSize(width: 320, height: 480),
        fontSize: 19,
        lineSpacing: 8,
        horizontalPadding: 20,
        verticalPadding: 20
    )

    func testShortAndEmptyTextAreSafe() async {
        let paginator = TextKitReaderPaginator()
        let shortPages = await paginator.paginate(text: "短正文🙂", configuration: configuration)
        let emptyPages = await paginator.paginate(text: "", configuration: configuration)
        XCTAssertEqual(shortPages.count, 1)
        XCTAssertEqual(shortPages[0].text, "短正文🙂")
        XCTAssertEqual(emptyPages.count, 1)
        XCTAssertEqual(emptyPages[0].utf16Range, 0..<0)
    }

    func testLongUnicodeTextProducesContinuousNonoverlappingPages() async {
        let paginator = TextKitReaderPaginator()
        let text = Array(repeating: "第一段中文🙂é，保留换行。\n第二段继续阅读。\n", count: 300).joined()
        let pages = await paginator.paginate(text: text, configuration: configuration)

        XCTAssertGreaterThan(pages.count, 1)
        XCTAssertEqual(pages.map(\.text).joined(), text)
        XCTAssertEqual(pages.first?.utf16Range.lowerBound, 0)
        XCTAssertEqual(pages.last?.utf16Range.upperBound, text.utf16.count)
        for pair in zip(pages, pages.dropFirst()) {
            XCTAssertEqual(pair.0.utf16Range.upperBound, pair.1.utf16Range.lowerBound)
        }
    }
}
