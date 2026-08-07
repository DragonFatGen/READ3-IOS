public struct BookSource: Codable, Equatable, Sendable {
    public var bookSourceUrl: String
    public var bookSourceName: String
    public var bookSourceGroup: String?
    public var bookSourceType: Int
    public var bookUrlPattern: String?
    public var customOrder: Int
    public var enabled: Bool
    public var enabledExplore: Bool
    public var concurrentRate: String?
    public var header: String?
    public var loginUrl: String?
    public var loginUi: String?
    public var loginCheckJs: String?
    public var bookSourceComment: String?
    public var lastUpdateTime: Int64
    public var respondTime: Int64
    public var weight: Int
    public var exploreUrl: String?
    public var ruleExplore: ExploreRule?
    public var searchUrl: String?
    public var ruleSearch: SearchRule?
    public var ruleBookInfo: BookInfoRule?
    public var ruleToc: TocRule?
    public var ruleContent: ContentRule?
    public var extraFields: [String: JSONValue]

    public init(
        bookSourceUrl: String = "",
        bookSourceName: String = "",
        bookSourceGroup: String? = nil,
        bookSourceType: Int = 0,
        bookUrlPattern: String? = nil,
        customOrder: Int = 0,
        enabled: Bool = true,
        enabledExplore: Bool = true,
        concurrentRate: String? = nil,
        header: String? = nil,
        loginUrl: String? = nil,
        loginUi: String? = nil,
        loginCheckJs: String? = nil,
        bookSourceComment: String? = nil,
        lastUpdateTime: Int64 = 0,
        respondTime: Int64 = 180_000,
        weight: Int = 0,
        exploreUrl: String? = nil,
        ruleExplore: ExploreRule? = nil,
        searchUrl: String? = nil,
        ruleSearch: SearchRule? = nil,
        ruleBookInfo: BookInfoRule? = nil,
        ruleToc: TocRule? = nil,
        ruleContent: ContentRule? = nil,
        extraFields: [String: JSONValue] = [:]
    ) {
        self.bookSourceUrl = bookSourceUrl
        self.bookSourceName = bookSourceName
        self.bookSourceGroup = bookSourceGroup
        self.bookSourceType = bookSourceType
        self.bookUrlPattern = bookUrlPattern
        self.customOrder = customOrder
        self.enabled = enabled
        self.enabledExplore = enabledExplore
        self.concurrentRate = concurrentRate
        self.header = header
        self.loginUrl = loginUrl
        self.loginUi = loginUi
        self.loginCheckJs = loginCheckJs
        self.bookSourceComment = bookSourceComment
        self.lastUpdateTime = lastUpdateTime
        self.respondTime = respondTime
        self.weight = weight
        self.exploreUrl = exploreUrl
        self.ruleExplore = ruleExplore
        self.searchUrl = searchUrl
        self.ruleSearch = ruleSearch
        self.ruleBookInfo = ruleBookInfo
        self.ruleToc = ruleToc
        self.ruleContent = ruleContent
        self.extraFields = extraFields
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case bookSourceUrl, bookSourceName, bookSourceGroup, bookSourceType
        case bookUrlPattern, customOrder, enabled, enabledExplore, concurrentRate
        case header, loginUrl, loginUi, loginCheckJs, bookSourceComment
        case lastUpdateTime, respondTime, weight, exploreUrl, ruleExplore
        case searchUrl, ruleSearch, ruleBookInfo, ruleToc, ruleContent
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bookSourceUrl = try container.decodeIfPresent(String.self, forKey: .bookSourceUrl) ?? ""
        bookSourceName = try container.decodeIfPresent(String.self, forKey: .bookSourceName) ?? ""
        bookSourceGroup = try container.decodeIfPresent(String.self, forKey: .bookSourceGroup)
        bookSourceType = try container.decodeIfPresent(Int.self, forKey: .bookSourceType) ?? 0
        bookUrlPattern = try container.decodeIfPresent(String.self, forKey: .bookUrlPattern)
        customOrder = try container.decodeIfPresent(Int.self, forKey: .customOrder) ?? 0
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        enabledExplore = try container.decodeIfPresent(Bool.self, forKey: .enabledExplore) ?? true
        concurrentRate = try container.decodeIfPresent(String.self, forKey: .concurrentRate)
        header = try container.decodeIfPresent(String.self, forKey: .header)
        loginUrl = try container.decodeIfPresent(String.self, forKey: .loginUrl)
        loginUi = try container.decodeIfPresent(String.self, forKey: .loginUi)
        loginCheckJs = try container.decodeIfPresent(String.self, forKey: .loginCheckJs)
        bookSourceComment = try container.decodeIfPresent(String.self, forKey: .bookSourceComment)
        lastUpdateTime = try container.decodeIfPresent(Int64.self, forKey: .lastUpdateTime) ?? 0
        respondTime = try container.decodeIfPresent(Int64.self, forKey: .respondTime) ?? 180_000
        weight = try container.decodeIfPresent(Int.self, forKey: .weight) ?? 0
        exploreUrl = try container.decodeIfPresent(String.self, forKey: .exploreUrl)
        ruleExplore = try container.decodeIfPresent(ExploreRule.self, forKey: .ruleExplore)
        searchUrl = try container.decodeIfPresent(String.self, forKey: .searchUrl)
        ruleSearch = try container.decodeIfPresent(SearchRule.self, forKey: .ruleSearch)
        ruleBookInfo = try container.decodeIfPresent(BookInfoRule.self, forKey: .ruleBookInfo)
        ruleToc = try container.decodeIfPresent(TocRule.self, forKey: .ruleToc)
        ruleContent = try container.decodeIfPresent(ContentRule.self, forKey: .ruleContent)
        extraFields = try decoder.decodeExtraFields(excluding: Self.knownKeys)
    }

    public func encode(to encoder: Encoder) throws {
        try encoder.encodeExtraFields(extraFields, excluding: Self.knownKeys)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bookSourceUrl, forKey: .bookSourceUrl)
        try container.encode(bookSourceName, forKey: .bookSourceName)
        try container.encodeIfPresent(bookSourceGroup, forKey: .bookSourceGroup)
        try container.encode(bookSourceType, forKey: .bookSourceType)
        try container.encodeIfPresent(bookUrlPattern, forKey: .bookUrlPattern)
        try container.encode(customOrder, forKey: .customOrder)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(enabledExplore, forKey: .enabledExplore)
        try container.encodeIfPresent(concurrentRate, forKey: .concurrentRate)
        try container.encodeIfPresent(header, forKey: .header)
        try container.encodeIfPresent(loginUrl, forKey: .loginUrl)
        try container.encodeIfPresent(loginUi, forKey: .loginUi)
        try container.encodeIfPresent(loginCheckJs, forKey: .loginCheckJs)
        try container.encodeIfPresent(bookSourceComment, forKey: .bookSourceComment)
        try container.encode(lastUpdateTime, forKey: .lastUpdateTime)
        try container.encode(respondTime, forKey: .respondTime)
        try container.encode(weight, forKey: .weight)
        try container.encodeIfPresent(exploreUrl, forKey: .exploreUrl)
        try container.encodeIfPresent(ruleExplore, forKey: .ruleExplore)
        try container.encodeIfPresent(searchUrl, forKey: .searchUrl)
        try container.encodeIfPresent(ruleSearch, forKey: .ruleSearch)
        try container.encodeIfPresent(ruleBookInfo, forKey: .ruleBookInfo)
        try container.encodeIfPresent(ruleToc, forKey: .ruleToc)
        try container.encodeIfPresent(ruleContent, forKey: .ruleContent)
    }

    private static let knownKeys = Set(CodingKeys.allCases.map(\.rawValue))
}
