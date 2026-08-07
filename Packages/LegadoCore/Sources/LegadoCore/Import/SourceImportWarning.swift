public struct SourceImportWarning: Codable, Equatable, Sendable {
    public enum Code: String, Codable, Sendable {
        case modernFieldWonConflict
        case unsupportedLegacyValuePreserved
        case numericValueCoerced
        case androidBehaviorDifference
    }

    public let code: Code
    public let field: String
    public let message: String

    public init(code: Code, field: String, message: String) {
        self.code = code
        self.field = field
        self.message = message
    }
}
