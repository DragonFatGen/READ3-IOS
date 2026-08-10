public struct RuleNodeExecutor: Sendable {
    private let selectorExecutor: any RuleNodeSelectorExecutor

    public init(selectorExecutor: any RuleNodeSelectorExecutor) {
        self.selectorExecutor = selectorExecutor
    }

    public func execute(
        _ expression: RuleExpression,
        input: RuleExecutionInput,
        context: inout RuleExecutionContext
    ) throws -> RuleNodeCollection {
        try evaluate(expression, input: input, context: &context)
    }

    private func evaluate(
        _ expression: RuleExpression,
        input: RuleExecutionInput,
        context: inout RuleExecutionContext
    ) throws -> RuleNodeCollection {
        switch expression {
        case .empty:
            return RuleNodeCollection(nodes: [])
        case let .selector(rule):
            return try selectorExecutor.selectNodes(selector: rule, input: input, context: context)
        case let .jsonPath(path):
            return try selectorExecutor.selectNodes(jsonPath: path, input: input, context: context)
        case let .xpath(path):
            return try selectorExecutor.selectNodes(xpath: path, input: input, context: context)
        case let .combination(.child, branches):
            let chain = try branches.map { expression -> SelectorRule in
                guard case let .selector(rule) = expression, rule.type == .legado else {
                    throw RuleExecutionError.unsupportedExecutionNode("non-selector node child chain")
                }
                return rule
            }
            return try selectorExecutor.selectNodes(childChain: chain, input: input, context: context)
        case let .combination(operation, branches):
            var collections: [[RuleNode]] = []
            for branch in branches {
                let nodes = try evaluate(branch, input: input, context: &context).nodes
                if !nodes.isEmpty {
                    collections.append(nodes)
                    if operation == .fallback { return RuleNodeCollection(nodes: nodes) }
                }
            }
            if operation == .interleave, let first = collections.first {
                var result: [RuleNode] = []
                for index in first.indices {
                    for collection in collections where collection.indices.contains(index) {
                        result.append(collection[index])
                    }
                }
                return RuleNodeCollection(nodes: result)
            }
            return RuleNodeCollection(nodes: collections.flatMap { $0 })
        default:
            throw RuleExecutionError.unsupportedExecutionNode("structured book-list expression")
        }
    }
}
