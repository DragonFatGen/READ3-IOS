import Foundation
import SwiftSoup

enum XPathValue {
    case element(Element)
    case string(String)
    case number(Double)
    case boolean(Bool)
}

struct XPathSubsetEvaluator {
    private let roots: [Element]

    init(document: Document) {
        roots = document.children().array()
    }

    func evaluate(_ expression: XPathExpression) throws -> [XPathValue] {
        switch expression {
        case let .path(path):
            return try evaluate(path, from: roots)
        case let .count(path):
            return [.number(Double(try evaluate(path, from: roots).count))]
        case let .contains(lhs, rhs):
            return [.boolean(try operandString(lhs, context: roots).contains(operandString(rhs, context: roots)))]
        case let .startsWith(lhs, rhs):
            return [.boolean(try operandString(lhs, context: roots).hasPrefix(operandString(rhs, context: roots)))]
        }
    }

    private func evaluate(_ path: XPathPath, from context: [Element]) throws -> [XPathValue] {
        var elements = context
        for (offset, step) in path.steps.enumerated() {
            let terminal = offset == path.steps.count - 1
            switch step.test {
            case let .element(name):
                elements = try selectElements(name: name, axis: step.axis, from: elements)
                elements = try apply(step.predicates, to: elements)
                if terminal { return elements.map(XPathValue.element) }
            case .current:
                guard step.predicates.isEmpty else { throw RuleExecutionError.unsupportedXPathFeature("predicate on .") }
                if terminal { return elements.map(XPathValue.element) }
            case .parent:
                guard step.predicates.isEmpty else { throw RuleExecutionError.unsupportedXPathFeature("predicate on ..") }
                elements = unique(elements.compactMap { $0.parent() })
                if terminal { return elements.map(XPathValue.element) }
            case let .attribute(name):
                guard terminal else { throw RuleExecutionError.xpathResultTypeMismatch("attribute is not a path context") }
                return try selectAttributes(name: name, axis: step.axis, from: elements).map(XPathValue.string)
            case .text:
                guard terminal else { throw RuleExecutionError.xpathResultTypeMismatch("text() is not an element context") }
                var values = try selectText(axis: step.axis, from: elements)
                values = try applyTextPredicates(step.predicates, to: values)
                return values.map(XPathValue.string)
            case .node:
                guard terminal else { throw RuleExecutionError.unsupportedXPathFeature("node() as an intermediate context") }
                return try selectNodes(axis: step.axis, from: elements)
            case .allText:
                guard terminal else { throw RuleExecutionError.xpathResultTypeMismatch("allText() is terminal") }
                return try selectedContexts(axis: step.axis, from: elements).map { .string(try $0.text()) }
            case .html:
                guard terminal else { throw RuleExecutionError.xpathResultTypeMismatch("html() is terminal") }
                return try selectedContexts(axis: step.axis, from: elements).map { .string(try $0.html()) }
            case .outerHTML:
                guard terminal else { throw RuleExecutionError.xpathResultTypeMismatch("outerHtml() is terminal") }
                return try selectedContexts(axis: step.axis, from: elements).map { .string(try $0.outerHtml()) }
            }
        }
        return elements.map(XPathValue.element)
    }

    private func selectElements(
        name: String,
        axis: XPathStep.Axis,
        from context: [Element]
    ) throws -> [Element] {
        switch axis {
        case .child:
            return context.flatMap { element in
                element.children().array().filter { name == "*" || $0.tagName() == name }
            }
        case .descendant:
            var result: [Element] = []
            for element in context {
                for candidate in try element.getAllElements().array()
                where name == "*" || candidate.tagName() == name {
                    result.append(candidate)
                }
            }
            return unique(result)
        }
    }

    private func selectAttributes(
        name: String,
        axis: XPathStep.Axis,
        from context: [Element]
    ) throws -> [String] {
        switch axis {
        case .child:
            if context.count == 1 { return [try context[0].attr(name)] }
            return try context.map { try $0.attr(name) }
        case .descendant:
            var result: [String] = []
            for element in context {
                for candidate in try element.getAllElements().array() where candidate.hasAttr(name) {
                    result.append(try candidate.attr(name))
                }
            }
            return result
        }
    }

    private func selectText(axis: XPathStep.Axis, from context: [Element]) throws -> [String] {
        switch axis {
        case .child:
            return context.flatMap { directText(from: $0) }
        case .descendant:
            return context.flatMap { recursiveText(from: $0) }
        }
    }

    private func directText(from element: Element) -> [String] {
        if element.tagName() == "script" { return [normalizeWhitespace(element.data())] }
        return element.textNodes().map { normalizeWhitespace($0.getWholeText()) }
    }

    private func recursiveText(from element: Element) -> [String] {
        if element.tagName() == "script" { return [normalizeWhitespace(element.data())] }
        var result: [String] = []
        for node in element.getChildNodes() {
            if let text = node as? TextNode {
                result.append(normalizeWhitespace(text.getWholeText()))
            } else if let child = node as? Element {
                result.append(contentsOf: recursiveText(from: child))
            }
        }
        return result
    }

    private func selectNodes(axis: XPathStep.Axis, from context: [Element]) throws -> [XPathValue] {
        let elements = selectedContexts(axis: axis, from: context)
        var result: [XPathValue] = []
        for element in elements {
            result.append(contentsOf: element.children().array().map(XPathValue.element))
            let ownText = element.ownText()
            if !ownText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(.string(ownText))
            }
        }
        return result
    }

    private func selectedContexts(axis: XPathStep.Axis, from context: [Element]) throws -> [Element] {
        switch axis {
        case .child: context
        case .descendant:
            try unique(context.flatMap { try $0.getAllElements().array() })
        }
    }

    private func apply(_ predicates: [String], to input: [Element]) throws -> [Element] {
        var values = input
        for predicate in predicates {
            if let position = Int(predicate) {
                values = values.filter { sameTagPosition($0) == position }
            } else if predicate == "last()" {
                values = values.filter { sameTagPosition($0) == sameTagCount($0) }
            } else if predicate.hasPrefix("position()") {
                guard let comparison = splitComparison(predicate), comparison.0 == "position()",
                      let number = Int(comparison.2), comparison.1 == "=" else {
                    throw RuleExecutionError.unsupportedXPathFeature("predicate [\(predicate)]")
                }
                values = values.filter { sameTagPosition($0) == number }
            } else if predicate.hasPrefix("contains(") {
                let arguments = try functionArguments(predicate, name: "contains")
                guard arguments.count == 2 else { throw RuleExecutionError.invalidXPath(predicate) }
                values = try values.filter {
                    try predicateOperand(arguments[0], element: $0).contains(unquote(arguments[1]))
                }
            } else if predicate.hasPrefix("starts-with(") {
                let arguments = try functionArguments(predicate, name: "starts-with")
                guard arguments.count == 2 else { throw RuleExecutionError.invalidXPath(predicate) }
                values = try values.filter {
                    try predicateOperand(arguments[0], element: $0).hasPrefix(unquote(arguments[1]))
                }
            } else if let comparison = splitComparison(predicate) {
                guard comparison.1 == "=" || comparison.1 == "!=" else {
                    throw RuleExecutionError.unsupportedXPathFeature("predicate [\(predicate)]")
                }
                values = try values.filter { element in
                    let matches = try predicateOperand(comparison.0, element: element) == unquote(comparison.2)
                    return comparison.1 == "=" ? matches : !matches
                }
            } else if predicate.hasPrefix("@") {
                let name = String(predicate.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                values = try values.filter { element in
                    guard element.hasAttr(name) else { return false }
                    return !(try element.attr(name)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            } else {
                throw RuleExecutionError.unsupportedXPathFeature("predicate [\(predicate)]")
            }
        }
        return values
    }

    private func applyTextPredicates(_ predicates: [String], to input: [String]) throws -> [String] {
        var values = input
        for predicate in predicates {
            if let position = Int(predicate), position > 0 {
                values = values.indices.contains(position - 1) ? [values[position - 1]] : []
            } else if predicate == "last()" {
                values = values.last.map { [$0] } ?? []
            } else {
                throw RuleExecutionError.unsupportedXPathFeature("text predicate [\(predicate)]")
            }
        }
        return values
    }

    private func predicateOperand(_ raw: String, element: Element) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("@") { return try element.attr(String(value.dropFirst())) }
        if value == "text()" {
            return element.textNodes().map { normalizeWhitespace($0.getWholeText()) }.joined(separator: ",")
        }
        if value == "." { return element.ownText() }
        return unquote(value)
    }

    private func operandString(_ operand: XPathOperand, context: [Element]) throws -> String {
        switch operand {
        case let .literal(value): value
        case let .path(path):
            let values = try evaluate(path, from: context)
            let separator = values.allSatisfy { value in
                if case .string = value { return true }
                return false
            } ? "," : ""
            return try values.map { value in
                switch value {
                case let .element(element): return element.ownText()
                case let .string(string): return string
                case let .number(number): return String(number)
                case let .boolean(boolean): return boolean ? "true" : "false"
                }
            }.joined(separator: separator)
        }
    }

    private func sameTagPosition(_ element: Element) -> Int {
        guard let parent = element.parent() else { return 1 }
        let siblings = parent.children().array().filter { $0.tagName() == element.tagName() }
        return (siblings.firstIndex { $0 === element } ?? 0) + 1
    }

    private func sameTagCount(_ element: Element) -> Int {
        guard let parent = element.parent() else { return 1 }
        return parent.children().array().filter { $0.tagName() == element.tagName() }.count
    }

    private func unique(_ elements: [Element]) -> [Element] {
        var result: [Element] = []
        for element in elements where !result.contains(where: { $0 === element }) { result.append(element) }
        return result
    }

    private func normalizeWhitespace(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private func splitComparison(_ value: String) -> (String, String, String)? {
        var quote: Character?
        let characters = Array(value)
        for index in characters.indices {
            let character = characters[index]
            if let active = quote { if character == active { quote = nil }; continue }
            if character == "'" || character == "\"" { quote = character; continue }
            if character == "=" {
                let isNot = index > 0 && characters[index - 1] == "!"
                let lhsEnd = isNot ? index - 1 : index
                return (
                    String(characters[..<lhsEnd]).trimmingCharacters(in: .whitespacesAndNewlines),
                    isNot ? "!=" : "=",
                    String(characters[(index + 1)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }
        return nil
    }

    private func functionArguments(_ value: String, name: String) throws -> [String] {
        guard value.hasPrefix("\(name)("), value.hasSuffix(")") else { throw RuleExecutionError.invalidXPath(value) }
        let start = value.index(value.startIndex, offsetBy: name.count + 1)
        let body = String(value[start..<value.index(before: value.endIndex)])
        var result: [String] = []
        var quote: Character?
        var split = body.startIndex
        var index = split
        while index < body.endIndex {
            let character = body[index]
            if let active = quote { if character == active { quote = nil } }
            else if character == "'" || character == "\"" { quote = character }
            else if character == "," { result.append(String(body[split..<index]).trimmingCharacters(in: .whitespacesAndNewlines)); split = body.index(after: index) }
            index = body.index(after: index)
        }
        guard quote == nil else { throw RuleExecutionError.invalidXPath(value) }
        result.append(String(body[split...]).trimmingCharacters(in: .whitespacesAndNewlines))
        return result
    }

    private func unquote(_ value: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 2, let first = value.first,
              (first == "'" || first == "\""), value.last == first else { return value }
        return String(value.dropFirst().dropLast())
    }
}
