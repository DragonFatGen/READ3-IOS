public struct SearchRule: Codable, Equatable, Sendable {
    public var checkKeyWord: String?
    public var bookList: String?
    public var name: String?
    public var author: String?
    public var intro: String?
    public var kind: String?
    public var lastChapter: String?
    public var updateTime: String?
    public var bookUrl: String?
    public var coverUrl: String?
    public var wordCount: String?
    public var extraFields: [String: JSONValue]

    public init(
        checkKeyWord: String? = nil,
        bookList: String? = nil,
        name: String? = nil,
        author: String? = nil,
        intro: String? = nil,
        kind: String? = nil,
        lastChapter: String? = nil,
        updateTime: String? = nil,
        bookUrl: String? = nil,
        coverUrl: String? = nil,
        wordCount: String? = nil,
        extraFields: [String: JSONValue] = [:]
    ) {
        self.checkKeyWord = checkKeyWord
        self.bookList = bookList
        self.name = name
        self.author = author
        self.intro = intro
        self.kind = kind
        self.lastChapter = lastChapter
        self.updateTime = updateTime
        self.bookUrl = bookUrl
        self.coverUrl = coverUrl
        self.wordCount = wordCount
        self.extraFields = extraFields
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case checkKeyWord, bookList, name, author, intro, kind, lastChapter
        case updateTime, bookUrl, coverUrl, wordCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        checkKeyWord = try container.decodeIfPresent(String.self, forKey: .checkKeyWord)
        bookList = try container.decodeIfPresent(String.self, forKey: .bookList)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        intro = try container.decodeIfPresent(String.self, forKey: .intro)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        lastChapter = try container.decodeIfPresent(String.self, forKey: .lastChapter)
        updateTime = try container.decodeIfPresent(String.self, forKey: .updateTime)
        bookUrl = try container.decodeIfPresent(String.self, forKey: .bookUrl)
        coverUrl = try container.decodeIfPresent(String.self, forKey: .coverUrl)
        wordCount = try container.decodeIfPresent(String.self, forKey: .wordCount)
        extraFields = try decoder.decodeExtraFields(excluding: Self.knownKeys)
    }

    public func encode(to encoder: Encoder) throws {
        try encoder.encodeExtraFields(extraFields, excluding: Self.knownKeys)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(checkKeyWord, forKey: .checkKeyWord)
        try container.encodeIfPresent(bookList, forKey: .bookList)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encodeIfPresent(intro, forKey: .intro)
        try container.encodeIfPresent(kind, forKey: .kind)
        try container.encodeIfPresent(lastChapter, forKey: .lastChapter)
        try container.encodeIfPresent(updateTime, forKey: .updateTime)
        try container.encodeIfPresent(bookUrl, forKey: .bookUrl)
        try container.encodeIfPresent(coverUrl, forKey: .coverUrl)
        try container.encodeIfPresent(wordCount, forKey: .wordCount)
    }

    private static let knownKeys = Set(CodingKeys.allCases.map(\.rawValue))
}
