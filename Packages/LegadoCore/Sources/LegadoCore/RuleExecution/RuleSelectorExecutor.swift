public protocol RuleSelectorExecutor: Sendable {
    func execute(
        selector: SelectorRule,
        input: RuleValue,
        context: RuleExecutionContext
    ) throws -> RuleValue

    func execute(
        childChain: [SelectorRule],
        input: RuleValue,
        context: RuleExecutionContext
    ) throws -> RuleValue

    func execute(jsonPath: String, input: RuleValue, context: RuleExecutionContext) throws -> RuleValue
    func execute(xpath: String, input: RuleValue, context: RuleExecutionContext) throws -> RuleValue
}

public extension RuleSelectorExecutor {
    func execute(
        childChain: [SelectorRule],
        input: RuleValue,
        context: RuleExecutionContext
    ) throws -> RuleValue {
        throw RuleExecutionError.unsupportedExecutionNode("historical selector child chain")
    }
}
