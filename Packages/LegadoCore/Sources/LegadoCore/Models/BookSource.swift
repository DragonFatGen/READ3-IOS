import Foundation

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
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)

        bookSourceUrl = try container.decodeIfPresent(String.self, forKey: .bookSourceUrl) ?? ""
        bookSourceName = try container.decodeIfPresent(String.self, forKey: .bookSourceName) ?? ""
        bookSourceGroup = try container.decodeIfPresent(String.self, forKey: .bookSourceGroup)
        bookSourceType = try Self.decodeSourceType(
            Self.value(for: CodingKeys.bookSourceType.rawValue, in: dynamicContainer)
        )
        bookUrlPattern = try container.decodeIfPresent(String.self, forKey: .bookUrlPattern)
        customOrder = try container.decodeIfPresent(Int.self, forKey: .customOrder) ?? 0
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        enabledExplore = try container.decodeIfPresent(Bool.self, forKey: .enabledExplore) ?? true
        concurrentRate = try container.decodeIfPresent(String.self, forKey: .concurrentRate)
        header = try container.decodeIfPresent(String.self, forKey: .header)
        loginUrl = try Self.decodeLoginURL(
            Self.value(for: CodingKeys.loginUrl.rawValue, in: dynamicContainer)
        )
        loginUi = try Self.decodeStringOrJSON(
            Self.value(for: CodingKeys.loginUi.rawValue, in: dynamicContainer),
            field: CodingKeys.loginUi.rawValue
        )
        loginCheckJs = try container.decodeIfPresent(String.self, forKey: .loginCheckJs)
        bookSourceComment = try container.decodeIfPresent(String.self, forKey: .bookSourceComment)
        lastUpdateTime = try container.decodeIfPresent(Int64.self, forKey: .lastUpdateTime) ?? 0
        respondTime = try container.decodeIfPresent(Int64.self, forKey: .respondTime) ?? 180_000
        weight = try container.decodeIfPresent(Int.self, forKey: .weight) ?? 0
        exploreUrl = try container.decodeIfPresent(String.self, forKey: .exploreUrl)
        ruleExplore = try Self.decodeRule(
            ExploreRule.self,
            from: Self.value(for: CodingKeys.ruleExplore.rawValue, in: dynamicContainer),
            field: CodingKeys.ruleExplore.rawValue
        )
        searchUrl = try container.decodeIfPresent(String.self, forKey: .searchUrl)
        ruleSearch = try Self.decodeRule(
            SearchRule.self,
            from: Self.value(for: CodingKeys.ruleSearch.rawValue, in: dynamicContainer),
            field: CodingKeys.ruleSearch.rawValue
        )
        ruleBookInfo = try Self.decodeRule(
            BookInfoRule.self,
            from: Self.value(for: CodingKeys.ruleBookInfo.rawValue, in: dynamicContainer),
            field: CodingKeys.ruleBookInfo.rawValue
        )
        ruleToc = try Self.decodeRule(
            TocRule.self,
            from: Self.value(for: CodingKeys.ruleToc.rawValue, in: dynamicContainer),
            field: CodingKeys.ruleToc.rawValue
        )
        ruleContent = try Self.decodeRule(
            ContentRule.self,
            from: Self.value(for: CodingKeys.ruleContent.rawValue, in: dynamicContainer),
            field: CodingKeys.ruleContent.rawValue
        )

        extraFields = try decoder.decodeExtraFields(excluding: Self.knownKeys)
        try applyLegacyFields(from: dynamicContainer, currentContainer: container)
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

    private mutating func applyLegacyFields(
        from values: KeyedDecodingContainer<DynamicCodingKey>,
        currentContainer: KeyedDecodingContainer<CodingKeys>
    ) throws {
        let legacyKeys = [
            "ruleBookUrlPattern", "serialNumber", "enable", "httpUserAgent",
            "ruleSearchUrl", "ruleFindUrl", "ruleSearchList", "ruleFindList",
            "ruleBookInfoInit", "ruleChapterList", "ruleBookContent"
        ]
        let isLegacy = legacyKeys.contains { values.contains(DynamicCodingKey($0)) }
        guard isLegacy else { return }

        if !currentContainer.contains(.bookUrlPattern) {
            bookUrlPattern = try Self.legacyString("ruleBookUrlPattern", in: values)
        }
        if !currentContainer.contains(.customOrder) {
            customOrder = try Self.legacyInt("serialNumber", in: values) ?? 0
        }
        if !currentContainer.contains(.enabled) {
            enabled = try Self.legacyBool("enable", in: values) ?? true
        }
        if !currentContainer.contains(.header),
           let userAgent = try Self.legacyString("httpUserAgent", in: values) {
            header = try Self.headerJSON(userAgent: userAgent)
        }
        if !currentContainer.contains(.searchUrl) {
            searchUrl = try Self.legacyString("ruleSearchUrl", in: values)
        }
        if !currentContainer.contains(.exploreUrl) {
            exploreUrl = try Self.legacyString("ruleFindUrl", in: values)
        }
        if !currentContainer.contains(.enabledExplore),
           exploreUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            enabledExplore = false
        }
        if !currentContainer.contains(.bookSourceComment), bookSourceComment == nil {
            bookSourceComment = ""
        }

        if !currentContainer.contains(.ruleSearch) {
            ruleSearch = try Self.legacySearchRule(from: values)
        }
        if !currentContainer.contains(.ruleExplore) {
            ruleExplore = try Self.legacyExploreRule(from: values)
        }
        if !currentContainer.contains(.ruleBookInfo) {
            ruleBookInfo = try Self.legacyBookInfoRule(from: values)
        }
        if !currentContainer.contains(.ruleToc) {
            ruleToc = try Self.legacyTocRule(from: values)
        }
        if !currentContainer.contains(.ruleContent) {
            ruleContent = try Self.legacyContentRule(from: values)
        }
    }

    private static func legacySearchRule(
        from values: KeyedDecodingContainer<DynamicCodingKey>
    ) throws -> SearchRule? {
        let rule = SearchRule(
            bookList: try legacyString("ruleSearchList", in: values),
            name: try legacyString("ruleSearchName", in: values),
            author: try legacyString("ruleSearchAuthor", in: values),
            intro: try legacyString("ruleSearchIntroduce", in: values),
            kind: try legacyString("ruleSearchKind", in: values),
            lastChapter: try legacyString("ruleSearchLastChapter", in: values),
            bookUrl: try legacyString("ruleSearchNoteUrl", in: values),
            coverUrl: try legacyString("ruleSearchCoverUrl", in: values)
        )
        return rule
    }

    private static func legacyExploreRule(
        from values: KeyedDecodingContainer<DynamicCodingKey>
    ) throws -> ExploreRule? {
        let rule = ExploreRule(
            bookList: try legacyString("ruleFindList", in: values),
            name: try legacyString("ruleFindName", in: values),
            author: try legacyString("ruleFindAuthor", in: values),
            intro: try legacyString("ruleFindIntroduce", in: values),
            kind: try legacyString("ruleFindKind", in: values),
            lastChapter: try legacyString("ruleFindLastChapter", in: values),
            bookUrl: try legacyString("ruleFindNoteUrl", in: values),
            coverUrl: try legacyString("ruleFindCoverUrl", in: values)
        )
        return rule
    }

    private static func legacyBookInfoRule(
        from values: KeyedDecodingContainer<DynamicCodingKey>
    ) throws -> BookInfoRule? {
        let rule = BookInfoRule(
            initialRule: try legacyString("ruleBookInfoInit", in: values),
            name: try legacyString("ruleBookName", in: values),
            author: try legacyString("ruleBookAuthor", in: values),
            intro: try legacyString("ruleIntroduce", in: values),
            kind: try legacyString("ruleBookKind", in: values),
            lastChapter: try legacyString("ruleBookLastChapter", in: values),
            coverUrl: try legacyString("ruleCoverUrl", in: values),
            tocUrl: try legacyString("ruleChapterUrl", in: values)
        )
        return rule
    }

    private static func legacyTocRule(
        from values: KeyedDecodingContainer<DynamicCodingKey>
    ) throws -> TocRule? {
        let rule = TocRule(
            chapterList: try legacyString("ruleChapterList", in: values),
            chapterName: try legacyString("ruleChapterName", in: values),
            chapterUrl: try legacyString("ruleContentUrl", in: values),
            nextTocUrl: try legacyString("ruleChapterUrlNext", in: values)
        )
        return rule
    }

    private static func legacyContentRule(
        from values: KeyedDecodingContainer<DynamicCodingKey>
    ) throws -> ContentRule? {
        let rule = ContentRule(
            content: try legacyString("ruleBookContent", in: values) ?? "",
            nextContentUrl: try legacyString("ruleContentUrlNext", in: values),
            replaceRegex: try legacyString("ruleBookContentReplace", in: values)
        )
        return rule
    }

    private static func value(
        for key: String,
        in container: KeyedDecodingContainer<DynamicCodingKey>
    ) throws -> JSONValue? {
        let codingKey = DynamicCodingKey(key)
        guard container.contains(codingKey) else { return nil }
        return try container.decode(JSONValue.self, forKey: codingKey)
    }

    private static func legacyString(
        _ key: String,
        in container: KeyedDecodingContainer<DynamicCodingKey>
    ) throws -> String? {
        guard let value = try value(for: key, in: container) else { return nil }
        switch value {
        case .null:
            return nil
        case let .string(string):
            return string
        default:
            throw typeMismatch(field: key, expected: "string", value: value)
        }
    }

    private static func legacyInt(
        _ key: String,
        in container: KeyedDecodingContainer<DynamicCodingKey>
    ) throws -> Int? {
        guard let value = try value(for: key, in: container) else { return nil }
        switch value {
        case .null:
            return nil
        case let .integer(integer):
            guard let result = Int(exactly: integer) else {
                throw typeMismatch(field: key, expected: "Int", value: value)
            }
            return result
        default:
            throw typeMismatch(field: key, expected: "Int", value: value)
        }
    }

    private static func legacyBool(
        _ key: String,
        in container: KeyedDecodingContainer<DynamicCodingKey>
    ) throws -> Bool? {
        guard let value = try value(for: key, in: container) else { return nil }
        switch value {
        case .null:
            return nil
        case let .bool(bool):
            return bool
        default:
            throw typeMismatch(field: key, expected: "Bool", value: value)
        }
    }

    private static func decodeSourceType(_ value: JSONValue?) throws -> Int {
        guard let value else { return 0 }
        switch value {
        case .null:
            return 0
        case let .integer(integer):
            guard let result = Int(exactly: integer) else {
                throw typeMismatch(field: "bookSourceType", expected: "Int", value: value)
            }
            return result
        case let .number(number):
            guard number.isFinite, number >= Double(Int.min), number <= Double(Int.max) else {
                throw typeMismatch(field: "bookSourceType", expected: "Int", value: value)
            }
            return Int(number)
        case let .string(string) where string.caseInsensitiveCompare("AUDIO") == .orderedSame:
            return 1
        case .string:
            return 0
        default:
            throw typeMismatch(field: "bookSourceType", expected: "Int or legacy type name", value: value)
        }
    }

    private static func decodeLoginURL(_ value: JSONValue?) throws -> String? {
        guard let value else { return nil }
        switch value {
        case .null:
            return nil
        case let .string(string):
            return string
        case let .object(object):
            guard let url = object["url"] else { return nil }
            guard case let .string(string) = url else {
                throw typeMismatch(field: "loginUrl.url", expected: "string", value: url)
            }
            return string
        default:
            throw typeMismatch(field: "loginUrl", expected: "string or object", value: value)
        }
    }

    private static func decodeStringOrJSON(_ value: JSONValue?, field: String) throws -> String? {
        guard let value else { return nil }
        switch value {
        case .null:
            return nil
        case let .string(string):
            return string
        case .array, .object:
            let data = try JSONEncoder().encode(value)
            guard let string = String(data: data, encoding: .utf8) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: [],
                    debugDescription: "Could not serialize \(field) as UTF-8"
                ))
            }
            return string
        default:
            throw typeMismatch(field: field, expected: "string, array, or object", value: value)
        }
    }

    private static func decodeRule<Rule: Decodable>(
        _ type: Rule.Type,
        from value: JSONValue?,
        field: String
    ) throws -> Rule? {
        guard let value else { return nil }
        switch value {
        case .null:
            return nil
        case .object:
            return try JSONDecoder().decode(type, from: JSONEncoder().encode(value))
        case let .string(json):
            guard let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        default:
            throw typeMismatch(field: field, expected: "object or JSON object string", value: value)
        }
    }

    private static func headerJSON(userAgent: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(["User-Agent": userAgent])
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(userAgent, .init(
                codingPath: [],
                debugDescription: "Could not serialize legacy User-Agent header"
            ))
        }
        return string
    }

    private static func typeMismatch(
        field: String,
        expected: String,
        value: JSONValue
    ) -> DecodingError {
        DecodingError.typeMismatch(JSONValue.self, .init(
            codingPath: [DynamicCodingKey(field)],
            debugDescription: "Expected \(expected) for \(field), found \(value)"
        ))
    }

    private static let knownKeys = Set(CodingKeys.allCases.map(\.rawValue))
}
