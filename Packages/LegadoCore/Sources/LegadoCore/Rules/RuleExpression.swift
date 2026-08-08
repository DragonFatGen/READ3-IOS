public indirect enum RuleExpression: Equatable, Sendable {
    case empty
    case selector(SelectorRule)
    case jsonPath(String)
    case xpath(String)
    case javaScript(String)
    case regex(RegexRule)
    case template(TemplateExpression)
    case sequence([RuleExpression])
    case combination(RuleOperator, [RuleExpression])
    case replacement(RuleExpression, RegexRule)
}

public struct SelectorRule: Equatable, Sendable {
    public let type: RuleSelectorType
    public let value: String

    public init(type: RuleSelectorType, value: String) {
        self.type = type
        self.value = value
    }
}

public enum RuleSelectorType: Equatable, Sendable {
    /// Legado's historical JSoup syntax, including tag/class/id shortcuts.
    case legado
    /// Explicit `@CSS:` JSoup selector syntax.
    case css
}

public enum RuleOperator: String, Equatable, Sendable {
    /// Append every non-empty branch result (`&&`).
    case concatenate = "&&"
    /// Use the first non-empty branch result (`||`).
    case fallback = "||"
    /// Interleave branch lists by index (`%%`).
    case interleave = "%%"
    /// Apply JSoup child selections from left to right (`@`).
    case child = "@"
}
