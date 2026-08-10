public struct JavaScriptExecutionContext: Sendable, Equatable {
    /// The value produced by the preceding rule stage and exposed as `result`.
    public let result: RuleValue
    public let baseUrl: String
    public let sourceVariables: [String: String]
    public let temporaryVariables: [String: String]

    public init(
        result: RuleValue,
        baseUrl: String,
        sourceVariables: [String: String] = [:],
        temporaryVariables: [String: String] = [:]
    ) {
        self.result = result
        self.baseUrl = baseUrl
        self.sourceVariables = sourceVariables
        self.temporaryVariables = temporaryVariables
    }

    init(ruleContext: RuleExecutionContext) {
        self.init(
            result: ruleContext.currentResult,
            baseUrl: ruleContext.baseUrl,
            sourceVariables: ruleContext.sourceVariables.snapshot,
            temporaryVariables: ruleContext.temporaryVariables.snapshot
        )
    }
}
