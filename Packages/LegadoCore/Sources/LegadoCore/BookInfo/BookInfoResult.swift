public struct BookInfoResult: Sendable, Equatable {
    public let name: String
    public let author: String
    public let bookURL: String
    public let coverURL: String?
    public let intro: String?
    public let kind: String?
    public let wordCount: String?
    public let lastChapter: String?
    public let tocURL: String
    public let sourceURL: String
    public let sourceName: String
    public let sourceType: Int
    public let sourceOrder: Int

    public init(
        name: String,
        author: String,
        bookURL: String,
        coverURL: String? = nil,
        intro: String? = nil,
        kind: String? = nil,
        wordCount: String? = nil,
        lastChapter: String? = nil,
        tocURL: String,
        sourceURL: String,
        sourceName: String,
        sourceType: Int,
        sourceOrder: Int
    ) {
        self.name = name
        self.author = author
        self.bookURL = bookURL
        self.coverURL = coverURL
        self.intro = intro
        self.kind = kind
        self.wordCount = wordCount
        self.lastChapter = lastChapter
        self.tocURL = tocURL
        self.sourceURL = sourceURL
        self.sourceName = sourceName
        self.sourceType = sourceType
        self.sourceOrder = sourceOrder
    }
}
