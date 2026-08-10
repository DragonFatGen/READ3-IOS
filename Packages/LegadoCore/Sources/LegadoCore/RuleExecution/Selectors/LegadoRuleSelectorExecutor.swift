public struct LegadoRuleSelectorExecutor: RuleNodeSelectorExecutor {
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

    public func execute(selector: SelectorRule, input: RuleExecutionInput, context: RuleExecutionContext) throws -> RuleValue {
        try jsoup.execute(selector: selector, input: input, context: context)
    }

    public func execute(childChain: [SelectorRule], input: RuleExecutionInput, context: RuleExecutionContext) throws -> RuleValue {
        try jsoup.execute(childChain: childChain, input: input, context: context)
    }

    public func execute(jsonPath path: String, input: RuleExecutionInput, context: RuleExecutionContext) throws -> RuleValue {
        try jsonPath.execute(jsonPath: path, input: input, context: context)
    }

    public func execute(xpath path: String, input: RuleExecutionInput, context: RuleExecutionContext) throws -> RuleValue {
        try xpath.execute(xpath: path, input: input, context: context)
    }

    public func selectNodes(selector: SelectorRule, input: RuleExecutionInput, context: RuleExecutionContext) throws -> RuleNodeCollection {
        try jsoup.selectNodes(selector: selector, input: input, context: context)
    }

    public func selectNodes(childChain: [SelectorRule], input: RuleExecutionInput, context: RuleExecutionContext) throws -> RuleNodeCollection {
        try jsoup.selectNodes(childChain: childChain, input: input, context: context)
    }

    public func selectNodes(jsonPath path: String, input: RuleExecutionInput, context: RuleExecutionContext) throws -> RuleNodeCollection {
        try jsonPath.selectNodes(jsonPath: path, input: input, context: context)
    }

    public func selectNodes(xpath path: String, input: RuleExecutionInput, context: RuleExecutionContext) throws -> RuleNodeCollection {
        try xpath.selectNodes(xpath: path, input: input, context: context)
    }

    public func selectContextNode(
        selector: SelectorRule,
        input: RuleExecutionInput,
        context: RuleExecutionContext
    ) throws -> RuleNode? {
        try jsoup.selectContextNode(selector: selector, input: input, context: context)
    }

    public func selectContextNode(jsonPath path: String, input: RuleExecutionInput, context: RuleExecutionContext) throws -> RuleNode? {
        try jsonPath.selectContextNode(jsonPath: path, input: input, context: context)
    }

    public func selectContextNode(xpath path: String, input: RuleExecutionInput, context: RuleExecutionContext) throws -> RuleNode? {
        try xpath.selectContextNode(xpath: path, input: input, context: context)
    }
}
