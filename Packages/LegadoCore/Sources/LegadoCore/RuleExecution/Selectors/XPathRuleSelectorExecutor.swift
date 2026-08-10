import SwiftSoup

public struct XPathRuleSelectorExecutor: RuleSelectorExecutor {
    public init() {}

    public func execute(selector: SelectorRule, input: RuleValue, context: RuleExecutionContext) throws -> RuleValue {
        throw RuleExecutionError.unsupportedExecutionNode("selector")
    }

    public func execute(jsonPath: String, input: RuleValue, context: RuleExecutionContext) throws -> RuleValue {
        throw RuleExecutionError.unsupportedExecutionNode("JSONPath")
    }

    public func execute(xpath path: String, input: RuleValue, context: RuleExecutionContext) throws -> RuleValue {
        guard !path.isEmpty else { return .none }
        do {
            let document = try SwiftSoup.parse(htmlInput(input))
            var parser = XPathSubsetParser(path)
            let expression = try parser.parse()
            let values = try XPathSubsetEvaluator(document: document).evaluate(expression)
            let strings = try values.map(serialize)
            return strings.isEmpty ? .none : .strings(strings)
        } catch let error as RuleExecutionError {
            throw error
        } catch {
            throw RuleExecutionError.invalidDocument(String(describing: error))
        }
    }

    public func execute(
        xpath path: String,
        input: RuleExecutionInput,
        context: RuleExecutionContext
    ) throws -> RuleValue {
        guard !path.isEmpty else { return .none }
        do {
            let root = try xpathRoot(input)
            return try root.owner.withLock {
                var parser = XPathSubsetParser(path)
                let values = try XPathSubsetEvaluator(roots: root.roots).evaluate(parser.parse())
                let strings = try values.map(serialize)
                return strings.isEmpty ? .none : .strings(strings)
            }
        } catch let error as RuleExecutionError {
            throw error
        } catch {
            throw RuleExecutionError.invalidDocument(String(describing: error))
        }
    }

    public func selectNodes(
        xpath path: String,
        input: RuleExecutionInput,
        context: RuleExecutionContext
    ) throws -> RuleNodeCollection {
        guard !path.isEmpty else { return RuleNodeCollection(nodes: []) }
        let root = try xpathRoot(input)
        return try root.owner.withLock {
            var parser = XPathSubsetParser(path)
            let values = try XPathSubsetEvaluator(roots: root.roots).evaluate(parser.parse())
            let elements = try values.map { value -> Element in
                guard case let .element(element) = value else {
                    throw RuleExecutionError.xpathResultTypeMismatch("book-list XPath must return element nodes")
                }
                return element
            }
            return RuleNodeCollection(nodes: elements.map {
                RuleNode(storage: .html(HTMLRuleNode(owner: root.owner, element: $0)))
            })
        }
    }

    private func htmlInput(_ input: RuleValue) -> String {
        let value: String
        switch input {
        case .none: value = ""
        case let .string(string): value = string
        case let .strings(strings): value = "[" + strings.joined(separator: ", ") + "]"
        }
        if value.hasSuffix("</td>") { return "<tr>\(value)</tr>" }
        if value.hasSuffix("</tr>") || value.hasSuffix("</tbody>") {
            return "<table>\(value)</table>"
        }
        return value
    }

    private func xpathRoot(
        _ input: RuleExecutionInput
    ) throws -> (owner: HTMLRuleNodeOwner, roots: [Element]) {
        if let node = input.node {
            guard case let .html(html) = node.storage else {
                throw RuleExecutionError.unsupportedExecutionNode("XPath over a JSON node")
            }
            return (html.owner, [html.element])
        }
        let document = try SwiftSoup.parse(htmlInput(input.value))
        return (HTMLRuleNodeOwner(retaining: [document]), document.children().array())
    }

    private func serialize(_ value: XPathValue) throws -> String {
        switch value {
        case let .element(element):
            return try element.outerHtml()
        case let .string(string):
            return string
        case let .number(number):
            // JsoupXpath's count(Integer) follows its Double branch because its
            // assignability check is reversed, producing values such as `2.0`.
            return String(number)
        case let .boolean(boolean):
            return boolean ? "true" : "false"
        }
    }
}
