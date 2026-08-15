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
}
