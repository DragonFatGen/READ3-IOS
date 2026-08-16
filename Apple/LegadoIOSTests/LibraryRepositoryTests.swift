import XCTest
@testable import LegadoIOS

@MainActor
final class LibraryRepositoryTests: XCTestCase {
    func testBookAndProgressPersist() {
        let suite = "LibraryRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = LibraryRepository(defaults: defaults, storageKey: "library")
        first.add(source: testSource(), bookInfo: testBookInfo())
        let bookID = first.books[0].id
        let progress = ReadingProgress(
            lastChapterURL: testChapter(index: 1).url,
            lastChapterName: testChapter(index: 1).name,
            lastChapterIndex: 1,
            chapterProgress: 0.35,
            chapterCount: 3,
            lastReadAt: Date()
        )
        first.saveProgress(progress, for: bookID)

        let restored = LibraryRepository(defaults: defaults, storageKey: "library")
        XCTAssertEqual(restored.books.count, 1)
        XCTAssertEqual(restored.progress(for: bookID), progress)
        XCTAssertEqual(restored.books[0].progress, progress)
    }

    func testNormalizedOverallProgressIsClamped() {
        let progress = ReadingProgress(
            lastChapterURL: "chapter", lastChapterName: "chapter",
            lastChapterIndex: 2, chapterProgress: 2, chapterCount: 3, lastReadAt: Date()
        )
        XCTAssertEqual(progress.normalizedChapterProgress, 1)
        XCTAssertEqual(progress.overallProgress, 1)
    }

    func testLegacyBookWithoutDatesDecodesAndProgressUpdatesLastReadAt() throws {
        let suite = "LibraryRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        var book = LibraryBook(source: testSource(), bookInfo: testBookInfo())
        let encoded = try JSONEncoder().encode([book])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        object[0].removeValue(forKey: "addedAt")
        object[0].removeValue(forKey: "lastReadAt")
        defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: "library")

        let repository = LibraryRepository(defaults: defaults, storageKey: "library")
        XCTAssertEqual(repository.books.first?.addedAt, .distantPast)
        XCTAssertNil(repository.books.first?.lastReadAt)

        let readAt = Date(timeIntervalSince1970: 1234)
        let progress = ReadingProgress(
            lastChapterURL: "chapter", lastChapterName: "第一章", lastChapterIndex: 0,
            chapterProgress: 0.5, chapterCount: 2, lastReadAt: readAt
        )
        book = try XCTUnwrap(repository.books.first)
        repository.saveProgress(progress, for: book.id)
        XCTAssertEqual(repository.books.first?.lastReadAt, readAt)
    }

    func testAllLibrarySortModesAreStable() {
        var oldest = LibraryBook(source: testSource(), bookInfo: testBookInfo(), addedAt: Date(timeIntervalSince1970: 1))
        var newest = LibraryBook(source: testSource(), bookInfo: testBookInfo(), addedAt: Date(timeIntervalSince1970: 3))
        oldest.name = "中文乙"
        newest.name = "中文甲"
        newest.bookURL = "https://source.example/book/2"
        newest.lastReadAt = Date(timeIntervalSince1970: 10)
        oldest.progress = ReadingProgress(
            lastChapterURL: "c", lastChapterName: "c", lastChapterIndex: 8,
            chapterProgress: 0, chapterCount: 10, lastReadAt: Date(timeIntervalSince1970: 2)
        )

        XCTAssertEqual([oldest, newest].sorted(by: .recentlyRead).first?.name, "中文甲")
        XCTAssertEqual([oldest, newest].sorted(by: .recentlyAdded).first?.name, "中文甲")
        let expectedTitle = [oldest.name, newest.name].min {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        XCTAssertEqual([oldest, newest].sorted(by: .title).first?.name, expectedTitle)
        XCTAssertEqual([newest, oldest].sorted(by: .progress).first?.name, "中文乙")
    }

    func testSortPreferencePersists() {
        let suite = "LibrarySortPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = LibrarySortPreference(defaults: defaults, storageKey: "sort")
        XCTAssertEqual(first.mode, .recentlyRead)
        first.mode = .progress
        XCTAssertEqual(LibrarySortPreference(defaults: defaults, storageKey: "sort").mode, .progress)
    }
}
