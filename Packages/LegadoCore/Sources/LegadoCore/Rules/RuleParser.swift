import Foundation

public struct RuleParseContext: Equatable, Sendable {
    public enum ErrorPolicy: Equatable, Sendable {
        /// Preserve malformed constructs as literals where Android does so.
        case legadoCompatible
        /// Diagnose malformed templates and empty combination branches.
        case strict
    }

    public let contentIsJSON: Bool
    public let allInOne: Bool
    public let errorPolicy: ErrorPolicy

    public init(
        contentIsJSON: Bool = false,
        allInOne: Bool = false,
        errorPolicy: ErrorPolicy = .legadoCompatible
    ) {
        self.contentIsJSON = contentIsJSON
        self.allInOne = allInOne
        self.errorPolicy = errorPolicy
    }
}

public struct RuleParser: Sendable {
    public init() {}

    public func parse(
        _ rule: String,
        context: RuleParseContext = RuleParseContext()
    ) throws -> RuleExpression {
        guard !rule.isEmpty else { return .empty }
        let segments = try splitJavaScriptSegments(rule, context: context)
        if segments.count == 1 { return segments[0] }
        return .sequence(segments)
    }

    public func tokenize(_ rule: String) -> [RuleToken] {
        let characters = Array(rule)
        var tokens: [RuleToken] = []
        var textStart = 0
        var index = 0

        func appendText(until end: Int) {
            guard end > textStart else { return }
            tokens.append(RuleToken(
                kind: .text,
                lexeme: String(characters[textStart..<end]),
                offset: textStart
            ))
        }

        while index < characters.count {
            let match: (RuleToken.Kind, String)?
            if matches("@js:", at: index, in: characters, caseInsensitive: true) {
                match = (.javaScriptStart, "@js:")
            } else if matches("<js>", at: index, in: characters, caseInsensitive: true) {
                match = (.javaScriptStart, "<js>")
            } else if matches("</js>", at: index, in: characters, caseInsensitive: true) {
                match = (.javaScriptEnd, "</js>")
            } else if matches("{{", at: index, in: characters) {
                match = (.templateStart, "{{")
            } else if matches("}}", at: index, in: characters) {
                match = (.templateEnd, "}}")
            } else if matches("&&", at: index, in: characters) {
                match = (.operatorSymbol(.concatenate), "&&")
            } else if matches("||", at: index, in: characters) {
                match = (.operatorSymbol(.fallback), "||")
            } else if matches("%%", at: index, in: characters) {
                match = (.operatorSymbol(.interleave), "%%")
            } else if matches("##", at: index, in: characters) {
                match = (.regexDelimiter, "##")
            } else if characters[index] == "@" {
                match = (.operatorSymbol(.child), "@")
            } else if characters[index] == "\\" {
                match = (.escape, "\\")
            } else {
                match = nil
            }

            if let match {
                appendText(until: index)
                tokens.append(RuleToken(kind: match.0, lexeme: match.1, offset: index))
                index += match.1.count
                textStart = index
            } else {
                index += 1
            }
        }
        appendText(until: characters.count)
        return tokens
    }

    private func splitJavaScriptSegments(
        _ rule: String,
        context: RuleParseContext
    ) throws -> [RuleExpression] {
        var result: [RuleExpression] = []
        var cursor = rule.startIndex

        while cursor < rule.endIndex {
            let searchRange = cursor..<rule.endIndex
            let tagRange = rule.range(of: "<js>", options: .caseInsensitive, range: searchRange)
            let prefixRange = rule.range(of: "@js:", options: .caseInsensitive, range: searchRange)
            let next = [tagRange, prefixRange].compactMap { $0 }.min { $0.lowerBound < $1.lowerBound }
            guard let next else { break }

            let isPrefix = String(rule[next]).lowercased() == "@js:"
            let close = isPrefix ? nil : rule.range(
                of: "</js>",
                options: .caseInsensitive,
                range: next.upperBound..<rule.endIndex
            )
            if !isPrefix && close == nil {
                // Android's JS_PATTERN does not match an unterminated <js> block.
                let literal = String(rule[cursor...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !literal.isEmpty { result.append(try parseSourceRule(literal, context: context)) }
                cursor = rule.endIndex
                break
            }

            if next.lowerBound > cursor {
                let preceding = String(rule[cursor..<next.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !preceding.isEmpty {
                    result.append(try parseSourceRule(preceding, context: context))
                }
            }

            if isPrefix {
                result.append(.javaScript(String(rule[next.upperBound...])))
                cursor = rule.endIndex
                break
            }

            guard let close else { break }
            result.append(.javaScript(String(rule[next.upperBound..<close.lowerBound])))
            cursor = close.upperBound
        }

        if cursor < rule.endIndex {
            let trailing = String(rule[cursor...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !trailing.isEmpty { result.append(try parseSourceRule(trailing, context: context)) }
        }
        return result.isEmpty ? [.empty] : result
    }

    private func parseSourceRule(
        _ rawRule: String,
        context: RuleParseContext
    ) throws -> RuleExpression {
        if context.allInOne && rawRule.hasPrefix(":") {
            let patterns = String(rawRule.dropFirst()).components(separatedBy: "&&").filter { !$0.isEmpty }
            return .regex(RegexRule(purpose: .extraction(patterns: patterns)))
        }

        let replacementParts = split(
            rawRule,
            on: "##",
            protectingTemplates: true,
            respectingEscapes: false
        )
        let baseText = replacementParts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        var expression = try parseTemplateOrCombination(baseText, context: context)
        if replacementParts.count > 1 {
            expression = .replacement(
                expression,
                RegexRule(purpose: .replacement(
                    pattern: replacementParts[1],
                    replacement: replacementParts.count > 2 ? replacementParts[2] : "",
                    replaceFirst: replacementParts.count > 3
                ))
            )
        }
        return expression
    }

    private func parseTemplateOrCombination(
        _ rule: String,
        context: RuleParseContext
    ) throws -> RuleExpression {
        if rule.contains("{{") {
            return .template(try parseTemplate(rule, context: context))
        }
        return try parseCombination(rule, context: context)
    }

    private func parseTemplate(
        _ rule: String,
        context: RuleParseContext
    ) throws -> TemplateExpression {
        var parts: [TemplateExpression.Part] = []
        var cursor = rule.startIndex
        while let open = rule.range(of: "{{", range: cursor..<rule.endIndex) {
            if open.lowerBound > cursor {
                parts.append(.literal(String(rule[cursor..<open.lowerBound])))
            }
            guard let close = rule.range(of: "}}", range: open.upperBound..<rule.endIndex) else {
                if context.errorPolicy == .strict {
                    throw RuleSyntaxError.unterminatedTemplate(offset: rule.distance(from: rule.startIndex, to: open.lowerBound))
                }
                parts.append(.literal(String(rule[open.lowerBound...])))
                cursor = rule.endIndex
                break
            }
            let body = String(rule[open.upperBound..<close.lowerBound])
            parts.append(.expression(try parseTemplateBody(body, context: context)))
            cursor = close.upperBound
        }
        if cursor < rule.endIndex { parts.append(.literal(String(rule[cursor...]))) }
        return TemplateExpression(parts: parts)
    }

    private func parseTemplateBody(
        _ body: String,
        context: RuleParseContext
    ) throws -> RuleExpression {
        if body.hasPrefix("@") || body.hasPrefix("$.") || body.hasPrefix("$[") || body.hasPrefix("//") {
            return try parseSourceRule(body, context: context)
        }
        return .javaScript(body)
    }

    private func parseCombination(
        _ rule: String,
        context: RuleParseContext
    ) throws -> RuleExpression {
        if rule.isEmpty { return .empty }
        if let found = try firstTopLevelOperator(in: rule, candidates: [.concatenate, .fallback, .interleave]) {
            let parts = split(rule, on: found.operator.rawValue, protectingTemplates: true, respectingGroups: true)
            if context.errorPolicy == .strict, parts.contains(where: { $0.isEmpty }) {
                throw RuleSyntaxError.invalidOperatorSequence(operator: found.operator, offset: found.offset)
            }
            return .combination(
                found.operator,
                try parts.map { try parseCombination($0, context: context) }
            )
        }
        return try parseLeaf(rule, context: context)
    }

    private func parseLeaf(_ original: String, context: RuleParseContext) throws -> RuleExpression {
        var rule = original.trimmingCharacters(in: .whitespacesAndNewlines)
        if rule.hasPrefix("@@") { rule.removeFirst(2) }
        if rule.lowercased().hasPrefix("@css:") {
            return .selector(SelectorRule(type: .css, value: String(rule.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        if rule.lowercased().hasPrefix("@xpath:") { return .xpath(String(rule.dropFirst(7))) }
        if rule.lowercased().hasPrefix("@json:") { return .jsonPath(String(rule.dropFirst(6))) }
        if context.contentIsJSON || rule.hasPrefix("$.") || rule.hasPrefix("$[") { return .jsonPath(rule) }
        if rule.hasPrefix("/") { return .xpath(rule) }

        if let child = try firstTopLevelOperator(in: rule, candidates: [.child]) {
            let parts = Array(
                split(rule, on: child.operator.rawValue, protectingTemplates: true, respectingGroups: true)
                    .drop(while: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            )
            if context.errorPolicy == .strict, parts.contains(where: { $0.isEmpty }) {
                throw RuleSyntaxError.invalidOperatorSequence(operator: .child, offset: child.offset)
            }
            return .combination(
                .child,
                parts.map { .selector(SelectorRule(type: .legado, value: $0)) }
            )
        }
        return .selector(SelectorRule(type: .legado, value: rule))
    }

    private func firstTopLevelOperator(
        in rule: String,
        candidates: [RuleOperator]
    ) throws -> (operator: RuleOperator, offset: Int)? {
        let chars = Array(rule)
        var stack: [(Character, Int)] = []
        var quote: Character?
        var escaped = false
        var templateDepth = 0
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if escaped { escaped = false; index += 1; continue }
            if char == "\\" { escaped = true; index += 1; continue }
            if let activeQuote = quote {
                if char == activeQuote { quote = nil }
                index += 1
                continue
            }
            if char == "\"" || char == "'" { quote = char; index += 1; continue }
            if matches("{{", at: index, in: chars) { templateDepth += 1; index += 2; continue }
            if templateDepth > 0 {
                if matches("}}", at: index, in: chars) { templateDepth -= 1; index += 2 } else { index += 1 }
                continue
            }
            if char == "[" || char == "(" { stack.append((char, index)); index += 1; continue }
            if char == "]" || char == ")" {
                if !stack.isEmpty { stack.removeLast() }
                index += 1
                continue
            }
            if stack.isEmpty {
                for candidate in candidates where matches(candidate.rawValue, at: index, in: chars) {
                    return (candidate, index)
                }
            }
            index += 1
        }
        if let unclosed = stack.last { throw RuleSyntaxError.unbalancedGroup(opening: unclosed.0, offset: unclosed.1) }
        return nil
    }

    private func split(
        _ value: String,
        on separator: String,
        protectingTemplates: Bool,
        respectingGroups: Bool = false,
        respectingEscapes: Bool = true
    ) -> [String] {
        let chars = Array(value)
        var result: [String] = []
        var start = 0
        var index = 0
        var depth = 0
        var templateDepth = 0
        var quote: Character?
        var escaped = false
        while index < chars.count {
            let char = chars[index]
            if respectingEscapes && escaped { escaped = false; index += 1; continue }
            if respectingEscapes && char == "\\" { escaped = true; index += 1; continue }
            if let activeQuote = quote {
                if char == activeQuote { quote = nil }
                index += 1
                continue
            }
            if char == "\"" || char == "'" { quote = char; index += 1; continue }
            if protectingTemplates && matches("{{", at: index, in: chars) { templateDepth += 1; index += 2; continue }
            if protectingTemplates && templateDepth > 0 {
                if matches("}}", at: index, in: chars) { templateDepth -= 1; index += 2 } else { index += 1 }
                continue
            }
            if respectingGroups {
                if char == "[" || char == "(" { depth += 1; index += 1; continue }
                if char == "]" || char == ")" { depth = max(0, depth - 1); index += 1; continue }
            }
            if depth == 0 && matches(separator, at: index, in: chars) {
                result.append(String(chars[start..<index]))
                index += separator.count
                start = index
            } else {
                index += 1
            }
        }
        result.append(String(chars[start..<chars.count]))
        return result
    }

    private func matches(
        _ needle: String,
        at index: Int,
        in characters: [Character],
        caseInsensitive: Bool = false
    ) -> Bool {
        let candidate = Array(needle)
        guard index + candidate.count <= characters.count else { return false }
        for offset in candidate.indices {
            let lhs = String(characters[index + offset])
            let rhs = String(candidate[offset])
            let isEqual = caseInsensitive ? lhs.lowercased() == rhs.lowercased() : lhs == rhs
            if !isEqual { return false }
        }
        return true
    }
}
