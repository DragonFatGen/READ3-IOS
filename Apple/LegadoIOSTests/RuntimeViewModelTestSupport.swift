import Foundation
import LegadoCore
@testable import LegadoIOS

enum ViewModelTestError: Error, Sendable {
    case expected
}

func testSource() -> BookSource {
    BookSource(bookSourceUrl: "https://source.example", bookSourceName: "测试书源")
}

func testSearchResult() -> BookSearchResult {
    BookSearchResult(
        name: "示例书籍",
        author: "作者",
        bookURL: "https://source.example/book/1",
        sourceURL: "https://source.example",
        sourceName: "测试书源",
        sourceType: 0,
        sourceOrder: 0
    )
}

func testBookInfo() -> BookInfoResult {
    BookInfoResult(
        name: "示例书籍",
        author: "作者",
        bookURL: "https://source.example/book/1",
        tocURL: "https://source.example/book/1/toc",
        sourceURL: "https://source.example",
        sourceName: "测试书源",
        sourceType: 0,
        sourceOrder: 0
    )
}

func testChapter(index: Int = 0) -> BookChapterResult {
    BookChapterResult(
        name: "第 \(index + 1) 章",
        url: "https://source.example/chapter/\(index + 1)",
        isVolume: false,
        index: index,
        bookURL: "https://source.example/book/1",
        sourceURL: "https://source.example"
    )
}

struct FakeBookInfoService: BookInfoLoading {
    let result: Result<BookInfoResult, ViewModelTestError>
    var delay: Duration = .zero

    func loadBookInfo(source: BookSource, book: BookSearchResult) async throws -> BookInfoResult {
        if delay > .zero { try await Task.sleep(for: delay) }
        return try result.get()
    }
}

struct FakeTOCService: TOCLoading {
    let result: Result<[BookChapterResult], ViewModelTestError>
    var delay: Duration = .zero

    func loadTOC(source: BookSource, book: BookInfoResult) async throws -> [BookChapterResult] {
        if delay > .zero { try await Task.sleep(for: delay) }
        return try result.get()
    }
}

struct FakeContentService: ChapterContentLoading {
    let result: Result<ChapterContentResult, ViewModelTestError>
    var delay: Duration = .zero

    func loadContent(
        source: BookSource,
        book: BookInfoResult,
        chapter: BookChapterResult,
        policy: ContentLoadPolicy
    ) async throws -> ChapterContentResult {
        _ = policy
        if delay > .zero { try await Task.sleep(for: delay) }
        return try result.get()
    }
}
