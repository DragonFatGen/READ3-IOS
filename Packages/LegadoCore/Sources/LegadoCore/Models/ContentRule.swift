public struct ContentRule: Codable, Equatable, Sendable {
    public var content: String?
    public var nextContentUrl: String?
    public var webJs: String?
    public var sourceRegex: String?
    public var replaceRegex: String?
    public var imageStyle: String?
    public var payAction: String?
    public var extraFields: [String: JSONValue]

    public init(
        content: String? = nil,
        nextContentUrl: String? = nil,
        webJs: String? = nil,
        sourceRegex: String? = nil,
        replaceRegex: String? = nil,
        imageStyle: String? = nil,
        payAction: String? = nil,
        extraFields: [String: JSONValue] = [:]
    ) {
        self.content = content
        self.nextContentUrl = nextContentUrl
        self.webJs = webJs
        self.sourceRegex = sourceRegex
        self.replaceRegex = replaceRegex
        self.imageStyle = imageStyle
        self.payAction = payAction
        self.extraFields = extraFields
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case content, nextContentUrl, webJs, sourceRegex, replaceRegex
        case imageStyle, payAction
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        nextContentUrl = try container.decodeIfPresent(String.self, forKey: .nextContentUrl)
        webJs = try container.decodeIfPresent(String.self, forKey: .webJs)
        sourceRegex = try container.decodeIfPresent(String.self, forKey: .sourceRegex)
        replaceRegex = try container.decodeIfPresent(String.self, forKey: .replaceRegex)
        imageStyle = try container.decodeIfPresent(String.self, forKey: .imageStyle)
        payAction = try container.decodeIfPresent(String.self, forKey: .payAction)
        extraFields = try decoder.decodeExtraFields(excluding: Self.knownKeys)
    }

    public func encode(to encoder: Encoder) throws {
        try encoder.encodeExtraFields(extraFields, excluding: Self.knownKeys)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(nextContentUrl, forKey: .nextContentUrl)
        try container.encodeIfPresent(webJs, forKey: .webJs)
        try container.encodeIfPresent(sourceRegex, forKey: .sourceRegex)
        try container.encodeIfPresent(replaceRegex, forKey: .replaceRegex)
        try container.encodeIfPresent(imageStyle, forKey: .imageStyle)
        try container.encodeIfPresent(payAction, forKey: .payAction)
    }

    private static let knownKeys = Set(CodingKeys.allCases.map(\.rawValue))
}
