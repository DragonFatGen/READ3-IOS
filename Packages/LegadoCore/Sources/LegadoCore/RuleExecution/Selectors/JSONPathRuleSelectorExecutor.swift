import Foundation

/// A deterministic, platform-neutral subset of Jayway JsonPath 2.7.0 used by
/// the pinned Android implementation. It intentionally has no shared state.
public struct JSONPathRuleSelectorExecutor: RuleSelectorExecutor {
    public init() {}

    public func execute(selector: SelectorRule, input: RuleValue, context: RuleExecutionContext) throws -> RuleValue {
        throw RuleExecutionError.unsupportedExecutionNode("selector")
    }

    public func execute(jsonPath path: String, input: RuleValue, context: RuleExecutionContext) throws -> RuleValue {
        do {
            let root = try decode(input)
            var parser = JSONPathParser(path)
            let query = try parser.parse()
            let values = try JSONPathEvaluator(root: root).evaluate(query)
            guard !values.isEmpty else { throw RuleExecutionError.pathNotFound(path) }
            let strings = values.flatMap(androidListProjection).map(androidString)
            return strings.isEmpty ? .none : .strings(strings)
        } catch let error as RuleExecutionError {
            if context.errorPolicy == .legadoCompatible { return .none }
            throw error
        } catch {
            if context.errorPolicy == .legadoCompatible { return .none }
            throw RuleExecutionError.invalidJSONPath(path)
        }
    }

    public func execute(xpath: String, input: RuleValue, context: RuleExecutionContext) throws -> RuleValue {
        throw RuleExecutionError.unsupportedExecutionNode("XPath")
    }

    private func decode(_ input: RuleValue) throws -> JSONValue {
        switch input {
        case .none:
            throw RuleExecutionError.invalidJSON("empty input")
        case let .string(value):
            guard let data = value.data(using: .utf8) else {
                throw RuleExecutionError.invalidJSON("input is not UTF-8")
            }
            do { return try JSONDecoder().decode(JSONValue.self, from: data) }
            catch { throw RuleExecutionError.invalidJSON(String(describing: error)) }
        case let .strings(values):
            // Android passes a List directly to JsonPath.parse rather than parsing
            // every list item as another JSON document.
            return .array(values.map(JSONValue.string))
        }
    }

    private func androidListProjection(_ value: JSONValue) -> [JSONValue] {
        if case let .array(values) = value { return values }
        return [value]
    }

    private func androidString(_ value: JSONValue) -> String {
        switch value {
        case .null:
            return "null"
        case let .bool(value):
            return value ? "true" : "false"
        case let .integer(value):
            return String(value)
        case let .number(value):
            return value.isFinite ? String(value) : "null"
        case let .string(value):
            return value
        case .array, .object:
            return compactJSON(value)
        }
    }

    private func compactJSON(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }
}
