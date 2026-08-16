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
    var lastReadAt: Date?
    var progress: ReadingProgress?
    var lastCheckedAt: Date?
    var lastKnownChapterCount: Int?
    var lastKnownLatestChapterURL: String?
    var lastKnownLatestChapterName: String?
    var updateCount: Int
    var lastUpdateError: String?

    var hasUpdate: Bool { updateCount > 0 }

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
        lastReadAt = nil
        lastCheckedAt = nil
        lastKnownChapterCount = nil
        lastKnownLatestChapterURL = nil
        lastKnownLatestChapterName = nil
        updateCount = 0
        lastUpdateError = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, source, name, author, bookURL, coverURL, intro, kind, wordCount
        case lastChapter, tocURL, sourceURL, sourceName, sourceType, sourceOrder
        case addedAt, lastReadAt, progress
        case lastCheckedAt, lastKnownChapterCount, lastKnownLatestChapterURL
        case lastKnownLatestChapterName, updateCount, lastUpdateError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        source = try container.decode(BookSource.self, forKey: .source)
        name = try container.decode(String.self, forKey: .name)
        author = try container.decode(String.self, forKey: .author)
        bookURL = try container.decode(String.self, forKey: .bookURL)
        coverURL = try container.decodeIfPresent(String.self, forKey: .coverURL)
        intro = try container.decodeIfPresent(String.self, forKey: .intro)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        wordCount = try container.decodeIfPresent(String.self, forKey: .wordCount)
        lastChapter = try container.decodeIfPresent(String.self, forKey: .lastChapter)
        tocURL = try container.decode(String.self, forKey: .tocURL)
        sourceURL = try container.decode(String.self, forKey: .sourceURL)
        sourceName = try container.decode(String.self, forKey: .sourceName)
        sourceType = try container.decode(Int.self, forKey: .sourceType)
        sourceOrder = try container.decode(Int.self, forKey: .sourceOrder)
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? .distantPast
        progress = try container.decodeIfPresent(ReadingProgress.self, forKey: .progress)
        lastReadAt = try container.decodeIfPresent(Date.self, forKey: .lastReadAt)
            ?? progress?.lastReadAt
        lastCheckedAt = try container.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
        lastKnownChapterCount = try container.decodeIfPresent(Int.self, forKey: .lastKnownChapterCount)
        lastKnownLatestChapterURL = try container.decodeIfPresent(
            String.self, forKey: .lastKnownLatestChapterURL
        )
        lastKnownLatestChapterName = try container.decodeIfPresent(
            String.self, forKey: .lastKnownLatestChapterName
        )
        updateCount = max(try container.decodeIfPresent(Int.self, forKey: .updateCount) ?? 0, 0)
        lastUpdateError = try container.decodeIfPresent(String.self, forKey: .lastUpdateError)
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
