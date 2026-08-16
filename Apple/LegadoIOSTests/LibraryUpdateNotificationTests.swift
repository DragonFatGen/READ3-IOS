import XCTest
@testable import LegadoIOS

final class LibraryUpdateNotificationTests: XCTestCase {
    func testNoDeltaProducesNoPayload() {
        XCTAssertNil(LibraryUpdateNotificationBuilder.make(updates: []))
        XCTAssertNil(LibraryUpdateNotificationBuilder.make(updates: [update(id: "1", count: 0)]))
    }

    func testSingleBookPayloadUsesStableIdentifierAndDelta() throws {
        let payload = try XCTUnwrap(LibraryUpdateNotificationBuilder.make(
            updates: [update(id: "book", count: 3, latest: "第 108 章")]
        ))
        XCTAssertEqual(payload.identifier, "library-update-book")
        XCTAssertEqual(payload.title, "《书 book》更新了 3 章")
        XCTAssertEqual(payload.body, "最新：第 108 章")
        XCTAssertEqual(payload.bookID, "book")
    }

    func testMultipleBooksProduceOneAggregatePayload() throws {
        let payload = try XCTUnwrap(LibraryUpdateNotificationBuilder.make(updates: [
            update(id: "1", count: 3), update(id: "2", count: 4), update(id: "3", count: 2)
        ]))
        XCTAssertEqual(payload.identifier, "library-update-summary")
        XCTAssertEqual(payload.title, "3 本书有新章节")
        XCTAssertEqual(payload.body, "共更新 9 章")
        XCTAssertNil(payload.bookID)
    }

    private func update(id: String, count: Int, latest: String? = nil) -> LibraryBookUpdateNotification {
        LibraryBookUpdateNotification(
            bookID: id, bookName: "书 \(id)", newChapterCount: count,
            latestChapterName: latest
        )
    }
}
