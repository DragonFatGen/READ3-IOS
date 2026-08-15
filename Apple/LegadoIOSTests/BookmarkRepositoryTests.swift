import XCTest
@testable import LegadoIOS

@MainActor
final class BookmarkRepositoryTests: XCTestCase {
    func testAddRemoveSortAndPersistenceRoundTrip() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let repository = BookmarkRepository(fileURL: fixture.file)
        let later = bookmark(chapter: 2, progress: 0.8)
        let earlier = bookmark(chapter: 1, progress: 0.4)
        let sameChapter = bookmark(chapter: 1, progress: 0.7)

        repository.add(later)
        repository.add(sameChapter)
        repository.add(earlier)
        XCTAssertEqual(repository.bookmarks(for: "book").map(\.id), [earlier.id, sameChapter.id, later.id])

        let restored = BookmarkRepository(fileURL: fixture.file)
        XCTAssertEqual(restored.bookmarks(for: "book").map(\.id), [earlier.id, sameChapter.id, later.id])
        restored.remove(id: sameChapter.id)
        XCTAssertEqual(restored.bookmarks(for: "book").count, 2)
        restored.removeAll(for: "book")
        XCTAssertTrue(restored.bookmarks(for: "book").isEmpty)
    }

    func testCorruptedPersistenceFallsBackToEmpty() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try Data("not-json".utf8).write(to: fixture.file)
        XCTAssertTrue(BookmarkRepository(fileURL: fixture.file).bookmarks(for: "book").isEmpty)
    }

    func testPreviewIsUnicodeSafeAndBounded() {
        let content = "第一段 😀 family 👨‍👩‍👧‍👦\n\n第二段继续阅读测试"
        let preview = BookmarkPreviewBuilder.makePreview(
            content: content,
            normalizedProgress: 0.5,
            characterLimit: 12
        )
        XCTAssertFalse(preview.isEmpty)
        XCTAssertLessThanOrEqual(preview.count, 14)
        XCTAssertFalse(preview.contains("\n"))
    }

    private func bookmark(chapter: Int, progress: Double) -> ReaderBookmark {
        ReaderBookmark(
            id: UUID(), bookID: "book", sourceIdentity: "source", bookIdentity: "url",
            chapterIndex: chapter, chapterURL: "chapter-\(chapter)",
            chapterName: "第 \(chapter) 章", chapterProgress: progress,
            previewText: "preview", createdAt: Date(timeIntervalSince1970: Double(chapter))
        )
    }

    private func makeFixture() throws -> (directory: URL, file: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookmarkRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appendingPathComponent("bookmarks.json"))
    }
}
