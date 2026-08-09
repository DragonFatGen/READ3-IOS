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

    private func serialize(_ value: XPathValue) throws -> String {
        switch value {
        case let .element(element): try element.outerHtml()
        case let .string(string): string
        case let .number(number):
            // JsoupXpath's count(Integer) follows its Double branch because its
            // assignability check is reversed, producing values such as `2.0`.
            String(number)
        case let .boolean(boolean): boolean ? "true" : "false"
        }
    }
}
