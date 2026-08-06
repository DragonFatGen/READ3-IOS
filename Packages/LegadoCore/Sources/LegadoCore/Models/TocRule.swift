public struct TocRule: Codable, Equatable, Sendable {
    public var chapterList: String?
    public var chapterName: String?
    public var chapterUrl: String?
    public var isVolume: String?
    public var isVip: String?
    public var isPay: String?
    public var updateTime: String?
    public var nextTocUrl: String?
    public var extraFields: [String: JSONValue]

    public init(
        chapterList: String? = nil,
        chapterName: String? = nil,
        chapterUrl: String? = nil,
        isVolume: String? = nil,
        isVip: String? = nil,
        isPay: String? = nil,
        updateTime: String? = nil,
        nextTocUrl: String? = nil,
        extraFields: [String: JSONValue] = [:]
    ) {
        self.chapterList = chapterList
        self.chapterName = chapterName
        self.chapterUrl = chapterUrl
        self.isVolume = isVolume
        self.isVip = isVip
        self.isPay = isPay
        self.updateTime = updateTime
        self.nextTocUrl = nextTocUrl
        self.extraFields = extraFields
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case chapterList, chapterName, chapterUrl, isVolume, isVip, isPay
        case updateTime, nextTocUrl
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chapterList = try container.decodeIfPresent(String.self, forKey: .chapterList)
        chapterName = try container.decodeIfPresent(String.self, forKey: .chapterName)
        chapterUrl = try container.decodeIfPresent(String.self, forKey: .chapterUrl)
        isVolume = try container.decodeIfPresent(String.self, forKey: .isVolume)
        isVip = try container.decodeIfPresent(String.self, forKey: .isVip)
        isPay = try container.decodeIfPresent(String.self, forKey: .isPay)
        updateTime = try container.decodeIfPresent(String.self, forKey: .updateTime)
        nextTocUrl = try container.decodeIfPresent(String.self, forKey: .nextTocUrl)
        extraFields = try decoder.decodeExtraFields(excluding: Self.knownKeys)
    }

    public func encode(to encoder: Encoder) throws {
        try encoder.encodeExtraFields(extraFields, excluding: Self.knownKeys)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(chapterList, forKey: .chapterList)
        try container.encodeIfPresent(chapterName, forKey: .chapterName)
        try container.encodeIfPresent(chapterUrl, forKey: .chapterUrl)
        try container.encodeIfPresent(isVolume, forKey: .isVolume)
        try container.encodeIfPresent(isVip, forKey: .isVip)
        try container.encodeIfPresent(isPay, forKey: .isPay)
        try container.encodeIfPresent(updateTime, forKey: .updateTime)
        try container.encodeIfPresent(nextTocUrl, forKey: .nextTocUrl)
    }

    private static let knownKeys = Set(CodingKeys.allCases.map(\.rawValue))
}
