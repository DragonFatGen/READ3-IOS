public struct RuleNodeExecutor: Sendable {
    private let selectorExecutor: any RuleNodeSelectorExecutor
    private let javaScriptExecutor: (any RuleJavaScriptExecutor)?

    public init(
        selectorExecutor: any RuleNodeSelectorExecutor,
        javaScriptExecutor: (any RuleJavaScriptExecutor)? = nil
    ) {
        self.selectorExecutor = selectorExecutor
        self.javaScriptExecutor = javaScriptExecutor
    }

    public func execute(
        _ expression: RuleExpression,
        input: RuleExecutionInput,
        context: inout RuleExecutionContext
    ) throws -> RuleNodeCollection {
        try evaluate(expression, input: input, context: &context)
    }

    /// Creates the parsed response context once so several field rules can share it.
    public func makeRootContext(
        input: RuleExecutionInput,
        contentIsJSON: Bool,
        context: inout RuleExecutionContext
    ) throws -> RuleExecutionInput {
        try selectorExecutor.makeRootContext(
            input: input,
            contentIsJSON: contentIsJSON,
            context: context
        )
    }

    /// Mirrors AnalyzeRule.getElement: selectors retain nodes, JSONPath retains the
    /// selected object/array/scalar, and scalar-only stages remain scalar.
    public func executeContext(
        _ expression: RuleExpression,
        input: RuleExecutionInput,
        context: inout RuleExecutionContext
    ) throws -> RuleExecutionInput {
        switch expression {
        case .empty:
            return input
        case let .selector(rule):
            return RuleExecutionInput(nodes: try selectorExecutor.selectNodes(
                selector: rule, input: input, context: context
            ))
        case let .jsonPath(path):
            return try selectorExecutor.selectContext(jsonPath: path, input: input, context: context)
        case let .xpath(path):
            return RuleExecutionInput(nodes: try selectorExecutor.selectNodes(
                xpath: path, input: input, context: context
            ))
        case .combination:
            return RuleExecutionInput(nodes: try evaluate(expression, input: input, context: &context))
        case let .sequence(expressions):
            var result = input
            for stage in expressions {
                if result.value == .none, !result.hasStructuredValue { break }
                result = try executeContext(stage, input: result, context: &context)
            }
            return result
        case let .variableWrite(assignments, body):
            let scalarExecutor = RuleExecutor(
                selectorExecutor: selectorExecutor,
                javaScriptExecutor: javaScriptExecutor
            )
            for assignment in assignments {
                let value = try scalarExecutor.execute(
                    assignment.value,
                    input: input,
                    context: &context
                ).value
                context.setTemporaryVariable(value.stringValue, named: assignment.key)
            }
            if case .empty = body { return input }
            return try executeContext(body, input: input, context: &context)
        default:
            let value = try RuleExecutor(
                selectorExecutor: selectorExecutor,
                javaScriptExecutor: javaScriptExecutor
            ).execute(
                expression,
                input: input,
                context: &context
            ).value
            return RuleExecutionInput(value)
        }
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
        case let .variableWrite(assignments, body):
            let scalarExecutor = RuleExecutor(
                selectorExecutor: selectorExecutor,
                javaScriptExecutor: javaScriptExecutor
            )
            for assignment in assignments {
                let value = try scalarExecutor.execute(
                    assignment.value,
                    input: input,
                    context: &context
                ).value
                context.setTemporaryVariable(value.stringValue, named: assignment.key)
            }
            return try evaluate(body, input: input, context: &context)
        default:
            throw RuleExecutionError.unsupportedExecutionNode("structured book-list expression")
        }
    }
}
