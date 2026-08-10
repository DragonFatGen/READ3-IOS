public struct TemplateExpression: Equatable, Sendable {
    public enum Part: Equatable, Sendable {
        case literal(String)
        case expression(RuleExpression)
    }

    public let parts: [Part]

    public init(parts: [Part]) {
        self.parts = parts
    }
}
