import Foundation
import LegadoCore

struct BookUpdateResult: Equatable, Sendable {
    let checkedAt: Date
    let chapterCount: Int
    let latestChapterName: String?
    let latestChapterURL: String?
    let newChapterCount: Int
}

enum BookUpdateCheckError: LocalizedError, Equatable, Sendable {
    case emptyTableOfContents

    var errorDescription: String? {
        switch self {
        case .emptyTableOfContents: "书源返回的目录为空"
        }
    }
}

protocol BookUpdateChecking: Sendable {
    func checkUpdate(for book: LibraryBook, source: BookSource) async throws -> BookUpdateResult
}

struct TOCBookUpdateChecker: BookUpdateChecking {
    let tocService: any TOCLoading
    let now: @Sendable () -> Date

    init(tocService: any TOCLoading, now: @escaping @Sendable () -> Date = Date.init) {
        self.tocService = tocService
        self.now = now
    }

    func checkUpdate(for book: LibraryBook, source: BookSource) async throws -> BookUpdateResult {
        let chapters = try await tocService.loadTOC(source: source, book: book.bookInfo)
        try Task.checkCancellation()
        guard let latest = chapters.last else { throw BookUpdateCheckError.emptyTableOfContents }
        return BookUpdateResult(
            checkedAt: now(),
            chapterCount: chapters.count,
            latestChapterName: latest.name,
            latestChapterURL: latest.url,
            newChapterCount: Self.newChapterCount(for: book, chapters: chapters)
        )
    }

    static func newChapterCount(for book: LibraryBook, chapters: [BookChapterResult]) -> Int {
        guard let oldCount = book.lastKnownChapterCount else { return 0 }
        if let oldLatestURL = book.lastKnownLatestChapterURL,
           let oldLatestIndex = chapters.lastIndex(where: { $0.url == oldLatestURL }) {
            let newURLs = chapters.dropFirst(oldLatestIndex + 1).map(\.url)
            return Set(newURLs).count
        }
        return max(chapters.count - oldCount, 0)
    }
}
