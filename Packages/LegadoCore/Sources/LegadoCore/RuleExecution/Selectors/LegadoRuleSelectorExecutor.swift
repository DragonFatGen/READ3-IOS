public struct LegadoRuleSelectorExecutor: RuleSelectorExecutor {
    private let jsoup = JSoupRuleSelectorExecutor()
    private let jsonPath = JSONPathRuleSelectorExecutor()

    public init() {}

    public func execute(selector: SelectorRule, input: RuleValue, context: RuleExecutionContext) throws -> RuleValue {
        try jsoup.execute(selector: selector, input: input, context: context)
    }

    public func execute(childChain: [SelectorRule], input: RuleValue, context: RuleExecutionContext) throws -> RuleValue {
        try jsoup.execute(childChain: childChain, input: input, context: context)
    }

    public func execute(jsonPath path: String, input: RuleValue, context: RuleExecutionContext) throws -> RuleValue {
        try jsonPath.execute(jsonPath: path, input: input, context: context)
    }

    public func execute(xpath: String, input: RuleValue, context: RuleExecutionContext) throws -> RuleValue {
        throw RuleExecutionError.unsupportedExecutionNode("XPath")
    }
}
