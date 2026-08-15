import LegadoCore

protocol BookSearching: Sendable {
    func search(source: BookSource, keyword: String) async throws -> [BookSearchResult]
}

protocol BookInfoLoading: Sendable {
    func loadBookInfo(source: BookSource, book: BookSearchResult) async throws -> BookInfoResult
}

protocol TOCLoading: Sendable {
    func loadTOC(source: BookSource, book: BookInfoResult) async throws -> [BookChapterResult]
}

enum ContentLoadPolicy: Equatable, Sendable {
    case cacheFirst
    case reloadIgnoringCache
}

protocol ChapterContentLoading: Sendable {
    func loadContent(
        source: BookSource,
        book: BookInfoResult,
        chapter: BookChapterResult,
        policy: ContentLoadPolicy
    ) async throws -> ChapterContentResult
}

extension ChapterContentLoading {
    func loadContent(
        source: BookSource,
        book: BookInfoResult,
        chapter: BookChapterResult
    ) async throws -> ChapterContentResult {
        try await loadContent(source: source, book: book, chapter: chapter, policy: .cacheFirst)
    }
}

struct LegadoSearchService: BookSearching {
    let runtime: BookSourceSearchRuntime

    func search(source: BookSource, keyword: String) async throws -> [BookSearchResult] {
        try await runtime.search(source: source, keyword: keyword)
    }
}

struct LegadoBookInfoService: BookInfoLoading {
    let runtime: BookSourceBookInfoRuntime

    func loadBookInfo(source: BookSource, book: BookSearchResult) async throws -> BookInfoResult {
        try await runtime.fetchBookInfo(source: source, book: book)
    }
}

struct LegadoTOCService: TOCLoading {
    let runtime: BookSourceTOCRuntime

    func loadTOC(source: BookSource, book: BookInfoResult) async throws -> [BookChapterResult] {
        try await runtime.fetchTOC(source: source, book: book)
    }
}

struct LegadoChapterContentService: ChapterContentLoading {
    let runtime: BookSourceContentRuntime

    func loadContent(
        source: BookSource,
        book: BookInfoResult,
        chapter: BookChapterResult,
        policy: ContentLoadPolicy
    ) async throws -> ChapterContentResult {
        _ = policy
        return try await runtime.fetchContent(source: source, book: book, chapter: chapter)
    }
}
