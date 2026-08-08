import Foundation

public struct RuleExecutor: Sendable {
    private let selectorExecutor: (any RuleSelectorExecutor)?

    public init(selectorExecutor: (any RuleSelectorExecutor)? = nil) {
        self.selectorExecutor = selectorExecutor
    }

    public func execute(
        _ expression: RuleExpression,
        input: RuleExecutionInput,
        context: inout RuleExecutionContext
    ) throws -> RuleExecutionResult {
        let value = try evaluate(expression, input: input.value, context: &context)
        context.currentResult = value
        return RuleExecutionResult(value: value, context: context)
    }

    private func evaluate(
        _ expression: RuleExpression,
        input: RuleValue,
        context: inout RuleExecutionContext
    ) throws -> RuleValue {
        context.currentResult = input
        switch expression {
        case .empty:
            return .none
        case let .selector(rule):
            guard let selectorExecutor else {
                throw RuleExecutionError.unsupportedExecutionNode("selector")
            }
            return try selectorExecutor.execute(selector: rule, input: input, context: context)
        case let .jsonPath(rule):
            guard let selectorExecutor else {
                throw RuleExecutionError.unsupportedExecutionNode("JSONPath")
            }
            return try selectorExecutor.execute(jsonPath: rule, input: input, context: context)
        case let .xpath(rule):
            guard let selectorExecutor else {
                throw RuleExecutionError.unsupportedExecutionNode("XPath")
            }
            return try selectorExecutor.execute(xpath: rule, input: input, context: context)
        case .javaScript(""):
            return .none
        case .javaScript:
            throw RuleExecutionError.unsupportedExecutionNode("JavaScript")
        case let .regex(rule):
            return try executeRegex(rule, on: input, context: &context)
        case let .replacement(base, rule):
            let baseValue = if case .empty = base {
                input
            } else {
                try evaluate(base, input: input, context: &context)
            }
            return try executeRegex(rule, on: baseValue, context: &context)
        case let .template(template):
            return try expand(template, input: input, context: &context)
        case let .sequence(expressions):
            var value = input
            for item in expressions {
                if value == .none { break }
                value = try evaluate(item, input: value, context: &context)
            }
            return value
        case let .combination(operation, branches):
            return try combine(operation, branches: branches, input: input, context: &context)
        case let .variableRead(key):
            return .string(context.variable(named: key) ?? "")
        case let .variableWrite(assignments, body):
            for assignment in assignments {
                let value = try evaluate(assignment.value, input: input, context: &context)
                context.setTemporaryVariable(value.stringValue, named: assignment.key)
            }
            if case .empty = body { return input }
            return try evaluate(body, input: input, context: &context)
        case let .captureGroup(index):
            guard context.captureGroups.indices.contains(index) else {
                if context.errorPolicy == .strict {
                    throw RuleExecutionError.invalidCaptureGroup(index)
                }
                return .string("$\(index)")
            }
            return .string(context.captureGroups[index])
        }
    }

    private func expand(
        _ template: TemplateExpression,
        input: RuleValue,
        context: inout RuleExecutionContext
    ) throws -> RuleValue {
        var result = ""
        for part in template.parts {
            switch part {
            case let .literal(value): result += value
            case let .expression(expression):
                result += try evaluate(expression, input: input, context: &context).stringValue
            }
        }
        // Android reparses rule-shaped bodies inside {{...}}, but does not reparse the
        // fully expanded outer string. Operators produced here therefore stay text.
        return .string(result)
    }

    private func combine(
        _ operation: RuleOperator,
        branches: [RuleExpression],
        input: RuleValue,
        context: inout RuleExecutionContext
    ) throws -> RuleValue {
        if operation == .child {
            guard let selectorExecutor else {
                throw RuleExecutionError.unsupportedExecutionNode("historical selector child chain")
            }
            let chain = try branches.map { branch -> SelectorRule in
                guard case let .selector(selector) = branch, selector.type == .legado else {
                    throw RuleExecutionError.unsupportedExecutionNode("non-selector child-chain node")
                }
                return selector
            }
            return try selectorExecutor.execute(childChain: chain, input: input, context: context)
        }
        var values: [RuleValue] = []
        for branch in branches {
            let value = try evaluate(branch, input: input, context: &context)
            if !value.isEmpty {
                values.append(value)
                if operation == .fallback { return value }
            }
        }
        guard !values.isEmpty else { return .none }
        if operation == .interleave {
            let lists = values.map(\.stringValues)
            var result: [String] = []
            for index in lists[0].indices {
                for list in lists where list.indices.contains(index) {
                    result.append(list[index])
                }
            }
            return .strings(result)
        }
        if values.count == 1 { return values[0] }
        return .strings(values.flatMap(\.stringValues))
    }

    private func executeRegex(
        _ rule: RegexRule,
        on input: RuleValue,
        context: inout RuleExecutionContext
    ) throws -> RuleValue {
        switch rule.purpose {
        case let .replacement(pattern, replacement, replaceFirst):
            let transformed = try input.stringValues.map {
                try replace(pattern: pattern, replacement: replacement, in: $0,
                            replaceFirst: replaceFirst, policy: context.errorPolicy)
            }
            if case .strings = input { return .strings(transformed) }
            return .string(transformed.first ?? "")
        case let .extraction(patterns):
            var source = input.stringValue
            context.captureGroups = []
            guard !patterns.isEmpty else { return .none }
            for (offset, pattern) in patterns.enumerated() {
                let regex = try compile(pattern, policy: context.errorPolicy)
                guard let regex else { return .none }
                let range = NSRange(source.startIndex..<source.endIndex, in: source)
                let matches = regex.matches(in: source, range: range)
                guard !matches.isEmpty else { return .none }
                if offset < patterns.count - 1 {
                    source = matches.compactMap { Range($0.range, in: source).map { String(source[$0]) } }.joined()
                } else {
                    var extracted: [String] = []
                    for match in matches {
                        var groups: [String] = []
                        for index in 0..<match.numberOfRanges {
                            let value = Range(match.range(at: index), in: source).map { String(source[$0]) } ?? ""
                            groups.append(value)
                            extracted.append(value)
                        }
                        if context.captureGroups.isEmpty { context.captureGroups = groups }
                    }
                    return .strings(extracted)
                }
            }
            return .none
        }
    }

    private func replace(
        pattern: String,
        replacement: String,
        in value: String,
        replaceFirst: Bool,
        policy: RuleParseContext.ErrorPolicy
    ) throws -> String {
        guard let regex = try compile(pattern, policy: policy) else {
            if replaceFirst, let range = value.range(of: pattern) {
                return String(value[..<range.lowerBound]) + replacement + String(value[range.upperBound...])
            }
            return value.replacingOccurrences(of: pattern, with: replacement)
        }
        let fullRange = NSRange(value.startIndex..<value.endIndex, in: value)
        if replaceFirst {
            guard let match = regex.firstMatch(in: value, range: fullRange),
                  let matchRange = Range(match.range, in: value) else { return "" }
            let matched = String(value[matchRange])
            return regex.stringByReplacingMatches(
                in: matched,
                range: NSRange(matched.startIndex..<matched.endIndex, in: matched),
                withTemplate: replacement
            )
        }
        return regex.stringByReplacingMatches(in: value, range: fullRange, withTemplate: replacement)
    }

    private func compile(
        _ pattern: String,
        policy: RuleParseContext.ErrorPolicy
    ) throws -> NSRegularExpression? {
        do { return try NSRegularExpression(pattern: pattern) }
        catch {
            if policy == .strict { throw RuleExecutionError.invalidRegularExpression(pattern) }
            return nil
        }
    }
}
