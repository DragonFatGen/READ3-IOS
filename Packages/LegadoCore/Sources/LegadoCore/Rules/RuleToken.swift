public struct RuleToken: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case text
        case javaScriptStart
        case javaScriptEnd
        case templateStart
        case templateEnd
        case operatorSymbol(RuleOperator)
        case regexDelimiter
        case escape
    }

    public let kind: Kind
    public let lexeme: String
    /// Character offset, deliberately independent of UTF-8/UTF-16 storage.
    public let offset: Int

    public init(kind: Kind, lexeme: String, offset: Int) {
        self.kind = kind
        self.lexeme = lexeme
        self.offset = offset
    }
}
