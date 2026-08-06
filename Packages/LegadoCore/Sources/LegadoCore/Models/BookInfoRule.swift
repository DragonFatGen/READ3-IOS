public struct BookInfoRule: Codable, Equatable, Sendable {
    public var `init`: String?
    public var name: String?
    public var author: String?
    public var intro: String?
    public var kind: String?
    public var lastChapter: String?
    public var updateTime: String?
    public var coverUrl: String?
    public var tocUrl: String?
    public var wordCount: String?
    public var canReName: String?
    public var extraFields: [String: JSONValue]

    public init(
        initialRule: String? = nil,
        name: String? = nil,
        author: String? = nil,
        intro: String? = nil,
        kind: String? = nil,
        lastChapter: String? = nil,
        updateTime: String? = nil,
        coverUrl: String? = nil,
        tocUrl: String? = nil,
        wordCount: String? = nil,
        canReName: String? = nil,
        extraFields: [String: JSONValue] = [:]
    ) {
        self.`init` = initialRule
        self.name = name
        self.author = author
        self.intro = intro
        self.kind = kind
        self.lastChapter = lastChapter
        self.updateTime = updateTime
        self.coverUrl = coverUrl
        self.tocUrl = tocUrl
        self.wordCount = wordCount
        self.canReName = canReName
        self.extraFields = extraFields
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case `init`, name, author, intro, kind, lastChapter, updateTime
        case coverUrl, tocUrl, wordCount, canReName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        `init` = try container.decodeIfPresent(String.self, forKey: .`init`)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        intro = try container.decodeIfPresent(String.self, forKey: .intro)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        lastChapter = try container.decodeIfPresent(String.self, forKey: .lastChapter)
        updateTime = try container.decodeIfPresent(String.self, forKey: .updateTime)
        coverUrl = try container.decodeIfPresent(String.self, forKey: .coverUrl)
        tocUrl = try container.decodeIfPresent(String.self, forKey: .tocUrl)
        wordCount = try container.decodeIfPresent(String.self, forKey: .wordCount)
        canReName = try container.decodeIfPresent(String.self, forKey: .canReName)
        extraFields = try decoder.decodeExtraFields(excluding: Self.knownKeys)
    }

    public func encode(to encoder: Encoder) throws {
        try encoder.encodeExtraFields(extraFields, excluding: Self.knownKeys)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(`init`, forKey: .`init`)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encodeIfPresent(intro, forKey: .intro)
        try container.encodeIfPresent(kind, forKey: .kind)
        try container.encodeIfPresent(lastChapter, forKey: .lastChapter)
        try container.encodeIfPresent(updateTime, forKey: .updateTime)
        try container.encodeIfPresent(coverUrl, forKey: .coverUrl)
        try container.encodeIfPresent(tocUrl, forKey: .tocUrl)
        try container.encodeIfPresent(wordCount, forKey: .wordCount)
        try container.encodeIfPresent(canReName, forKey: .canReName)
    }

    private static let knownKeys = Set(CodingKeys.allCases.map(\.rawValue))
}
