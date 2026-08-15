import Foundation
import LegadoCore

struct ReadingProgress: Codable, Equatable, Sendable {
    var lastChapterURL: String
    var lastChapterName: String
    var lastChapterIndex: Int
    var chapterProgress: Double
    var chapterCount: Int
    var lastReadAt: Date

    var normalizedChapterProgress: Double { min(max(chapterProgress, 0), 1) }

    var overallProgress: Double? {
        guard chapterCount > 0 else { return nil }
        return min(max((Double(lastChapterIndex) + normalizedChapterProgress) / Double(chapterCount), 0), 1)
    }
}

struct LibraryBook: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var source: BookSource
    var name: String
    var author: String
    var bookURL: String
    var coverURL: String?
    var intro: String?
    var kind: String?
    var wordCount: String?
    var lastChapter: String?
    var tocURL: String
    var sourceURL: String
    var sourceName: String
    var sourceType: Int
    var sourceOrder: Int
    var addedAt: Date
    var progress: ReadingProgress?

    init(source: BookSource, bookInfo: BookInfoResult, addedAt: Date = Date()) {
        id = Self.identifier(sourceURL: source.bookSourceUrl, bookURL: bookInfo.bookURL)
        self.source = source
        name = bookInfo.name
        author = bookInfo.author
        bookURL = bookInfo.bookURL
        coverURL = bookInfo.coverURL
        intro = bookInfo.intro
        kind = bookInfo.kind
        wordCount = bookInfo.wordCount
        lastChapter = bookInfo.lastChapter
        tocURL = bookInfo.tocURL
        sourceURL = bookInfo.sourceURL
        sourceName = bookInfo.sourceName
        sourceType = bookInfo.sourceType
        sourceOrder = bookInfo.sourceOrder
        self.addedAt = addedAt
    }

    var bookInfo: BookInfoResult {
        BookInfoResult(
            name: name, author: author, bookURL: bookURL, coverURL: coverURL,
            intro: intro, kind: kind, wordCount: wordCount, lastChapter: lastChapter,
            tocURL: tocURL, sourceURL: sourceURL, sourceName: sourceName,
            sourceType: sourceType, sourceOrder: sourceOrder
        )
    }

    static func identifier(sourceURL: String, bookURL: String) -> String {
        "\(sourceURL)|\(bookURL)"
    }
}
