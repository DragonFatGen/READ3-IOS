public struct RuleExecutionResult: Sendable, Equatable {
    public let value: RuleValue
    public let context: RuleExecutionContext

    public init(value: RuleValue, context: RuleExecutionContext) {
        self.value = value
        self.context = context
    }
}
