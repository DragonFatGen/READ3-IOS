import Foundation
import XCTest
@testable import LegadoIOS

@MainActor
final class ReaderAnnotationRepositoryTests: XCTestCase {
    func testCreateSaveRestoreAndDeleteHighlight() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let repository = ReaderAnnotationRepository(fileURL: fixture.file)
        let annotation = makeAnnotation(chapter: 0, location: 2)

        repository.save(annotation)
        XCTAssertEqual(repository.annotations(for: "book"), [annotation])
        XCTAssertEqual(ReaderAnnotationRepository(fileURL: fixture.file).annotations(for: "book"), [annotation])

        repository.remove(id: annotation.id)
        XCTAssertTrue(repository.annotations(for: "book").isEmpty)
    }

    func testMultipleHighlightsSortWithinSameChapter() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let repository = ReaderAnnotationRepository(fileURL: fixture.file)
        let later = makeAnnotation(chapter: 0, location: 12)
        let earlier = makeAnnotation(chapter: 0, location: 2)
        repository.save(later)
        repository.save(earlier)

        XCTAssertEqual(repository.annotations(for: "book").map(\.id), [earlier.id, later.id])
    }

    func testHighlightsRemainSeparatedAcrossChapters() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let repository = ReaderAnnotationRepository(fileURL: fixture.file)
        let second = makeAnnotation(chapter: 1, location: 1)
        let first = makeAnnotation(chapter: 0, location: 8)
        repository.save(second)
        repository.save(first)

        XCTAssertEqual(repository.annotations(for: "book").map(\.chapterIndex), [0, 1])
    }

    func testNoteAndStyleUpdatePersist() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let repository = ReaderAnnotationRepository(fileURL: fixture.file)
        var annotation = makeAnnotation(chapter: 0, location: 2)
        repository.save(annotation)
        annotation.note = "这一段很重要"
        annotation.style = .blue
        annotation.updatedAt = Date(timeIntervalSince1970: 20)
        repository.save(annotation)

        let restored = try XCTUnwrap(
            ReaderAnnotationRepository(fileURL: fixture.file).annotations(for: "book").first
        )
        XCTAssertEqual(restored.note, "这一段很重要")
        XCTAssertEqual(restored.style, .blue)
    }

    func testCorruptedJSONFallsBackToEmptyCollection() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try Data("not-json".utf8).write(to: fixture.file)
        XCTAssertTrue(
            ReaderAnnotationRepository(fileURL: fixture.file).annotations(for: "book").isEmpty
        )
    }

    func testRemovingLibraryBookClearsOnlyOwnedAnnotations() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let repository = ReaderAnnotationRepository(fileURL: fixture.file)
        repository.save(makeAnnotation(chapter: 0, location: 2, bookID: "book"))
        repository.save(makeAnnotation(chapter: 0, location: 2, bookID: "other"))

        repository.removeAll(for: "book")
        XCTAssertTrue(repository.annotations(for: "book").isEmpty)
        XCTAssertEqual(repository.annotations(for: "other").count, 1)
    }

    func testUTF16RangeValidationAndNearestTextRecoveryAreSafe() {
        let content = "甲😀乙，重复。重复。"
        let source = content as NSString
        let emojiRange = source.range(of: "😀乙")
        let exact = makeAnnotation(
            chapter: 0,
            location: emojiRange.location,
            length: emojiRange.length,
            selectedText: "😀乙",
            chapterLength: source.length
        )
        XCTAssertEqual(exact.resolvedRange(in: content), emojiRange)

        let splitSurrogate = makeAnnotation(
            chapter: 0,
            location: emojiRange.location,
            length: 1,
            selectedText: "不存在",
            chapterLength: source.length
        )
        XCTAssertNil(splitSurrogate.resolvedRange(in: content))

        let moved = makeAnnotation(
            chapter: 0,
            location: source.length - 1,
            length: 2,
            selectedText: "重复",
            chapterLength: source.length
        )
        XCTAssertEqual(moved.resolvedRange(in: content), source.range(of: "重复", options: .backwards))
    }

    func testOverflowingPersistedRangeSafelyUsesTextRecovery() {
        let annotation = makeAnnotation(
            chapter: 0,
            location: Int.max,
            length: 2,
            selectedText: "甲",
            chapterLength: 1
        )

        XCTAssertEqual(annotation.utf16Range, 0..<0)
        XCTAssertEqual(annotation.resolvedRange(in: "甲"), NSRange(location: 0, length: 1))
    }

    func testScrollAndPagedRangesMapFromChapterUTF16Offsets() {
        let content = "零一二三四五"
        let annotation = makeAnnotation(
            chapter: 0,
            location: 2,
            length: 3,
            selectedText: "二三四",
            chapterLength: (content as NSString).length
        )
        let scroll = ReaderAnnotationRangeMapper.spans(
            annotations: [annotation],
            fullText: content,
            displayedUTF16Range: 0..<(content as NSString).length
        )
        XCTAssertEqual(scroll.first?.localUTF16Range, NSRange(location: 2, length: 3))

        let page = ReaderAnnotationRangeMapper.spans(
            annotations: [annotation],
            fullText: content,
            displayedUTF16Range: 3..<6
        )
        XCTAssertEqual(page.first?.localUTF16Range, NSRange(location: 0, length: 2))
    }

    private func makeAnnotation(
        chapter: Int,
        location: Int,
        length: Int = 2,
        selectedText: String = "正文",
        chapterLength: Int = 100,
        bookID: String = "book"
    ) -> ReaderAnnotation {
        ReaderAnnotation(
            id: UUID(), bookID: bookID, sourceIdentity: "source", bookIdentity: "book-url",
            chapterIndex: chapter, chapterURL: "chapter-\(chapter)", chapterName: "第 \(chapter) 章",
            utf16Location: location, utf16Length: length, chapterUTF16Length: chapterLength,
            selectedText: selectedText, style: .yellow, note: nil,
            createdAt: Date(timeIntervalSince1970: Double(chapter)),
            updatedAt: Date(timeIntervalSince1970: Double(chapter))
        )
    }

    private func makeFixture() throws -> (directory: URL, file: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ReaderAnnotationRepositoryTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appendingPathComponent("annotations.json"))
    }
}
