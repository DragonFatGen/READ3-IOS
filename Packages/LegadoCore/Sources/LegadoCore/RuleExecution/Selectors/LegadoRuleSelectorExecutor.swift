public struct LegadoRuleSelectorExecutor: RuleSelectorExecutor {
    private let jsoup = JSoupRuleSelectorExecutor()
    private let jsonPath = JSONPathRuleSelectorExecutor()
    private let xpath = XPathRuleSelectorExecutor()

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

    public func execute(xpath path: String, input: RuleValue, context: RuleExecutionContext) throws -> RuleValue {
        try xpath.execute(xpath: path, input: input, context: context)
    }
}
