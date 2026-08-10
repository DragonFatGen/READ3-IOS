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

/// Optional structured-node capability used by runtime orchestration. Existing scalar
/// selector executors and test fakes do not need to implement it.
public protocol RuleNodeSelectorExecutor: RuleSelectorExecutor {
    func execute(
        selector: SelectorRule,
        input: RuleExecutionInput,
        context: RuleExecutionContext
    ) throws -> RuleValue

    func execute(
        childChain: [SelectorRule],
        input: RuleExecutionInput,
        context: RuleExecutionContext
    ) throws -> RuleValue

    func execute(jsonPath: String, input: RuleExecutionInput, context: RuleExecutionContext) throws -> RuleValue
    func execute(xpath: String, input: RuleExecutionInput, context: RuleExecutionContext) throws -> RuleValue

    func selectNodes(
        selector: SelectorRule,
        input: RuleExecutionInput,
        context: RuleExecutionContext
    ) throws -> RuleNodeCollection

    func selectNodes(
        childChain: [SelectorRule],
        input: RuleExecutionInput,
        context: RuleExecutionContext
    ) throws -> RuleNodeCollection

    func selectNodes(jsonPath: String, input: RuleExecutionInput, context: RuleExecutionContext) throws -> RuleNodeCollection
    func selectNodes(xpath: String, input: RuleExecutionInput, context: RuleExecutionContext) throws -> RuleNodeCollection

    func selectContextNode(
        selector: SelectorRule,
        input: RuleExecutionInput,
        context: RuleExecutionContext
    ) throws -> RuleNode?
    func selectContextNode(jsonPath: String, input: RuleExecutionInput, context: RuleExecutionContext) throws -> RuleNode?
    func selectContextNode(xpath: String, input: RuleExecutionInput, context: RuleExecutionContext) throws -> RuleNode?
}

public extension RuleNodeSelectorExecutor {
    func selectContextNode(
        selector: SelectorRule,
        input: RuleExecutionInput,
        context: RuleExecutionContext
    ) throws -> RuleNode? {
        RuleNode.context(try selectNodes(selector: selector, input: input, context: context).nodes)
    }

    func selectContextNode(jsonPath: String, input: RuleExecutionInput, context: RuleExecutionContext) throws -> RuleNode? {
        RuleNode.context(try selectNodes(jsonPath: jsonPath, input: input, context: context).nodes)
    }

    func selectContextNode(xpath: String, input: RuleExecutionInput, context: RuleExecutionContext) throws -> RuleNode? {
        RuleNode.context(try selectNodes(xpath: xpath, input: input, context: context).nodes)
    }
}
