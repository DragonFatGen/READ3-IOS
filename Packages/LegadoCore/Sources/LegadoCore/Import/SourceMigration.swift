public struct SourceMigration: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case legacyField
        case legacyRuleGroup
        case stringRuleObject
        case legacySourceType
        case loginURLRepresentation
        case numericCoercion
        case emptyExploreURL
        case discardedLegacyConflict
    }

    public let kind: Kind
    public let sourceFields: [String]
    public let destinationField: String
    public let message: String

    public init(
        kind: Kind,
        sourceFields: [String],
        destinationField: String,
        message: String
    ) {
        self.kind = kind
        self.sourceFields = sourceFields
        self.destinationField = destinationField
        self.message = message
    }
}
