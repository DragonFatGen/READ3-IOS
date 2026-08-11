import Foundation

/// A deterministic, platform-neutral subset of Jayway JsonPath 2.7.0 used by
/// the pinned Android implementation. It intentionally has no shared state.
public struct JSONPathRuleSelectorExecutor: RuleSelectorExecutor {
    public init() {}

    public func makeRootContext(
        input: RuleExecutionInput,
        contentIsJSON: Bool,
        context: RuleExecutionContext
    ) throws -> RuleExecutionInput {
        RuleExecutionInput(node: RuleNode(storage: .json(try decode(input))))
    }

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

    public func execute(
        jsonPath path: String,
        input: RuleExecutionInput,
        context: RuleExecutionContext
    ) throws -> RuleValue {
        do {
            let root = try decode(input)
            let values = try evaluate(path, root: root)
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

    public func selectNodes(
        jsonPath path: String,
        input: RuleExecutionInput,
        context: RuleExecutionContext
    ) throws -> RuleNodeCollection {
        do {
            let values = try evaluate(path, root: decode(input))
            let items: [JSONValue]
            if values.count == 1, case let .array(array) = values[0] {
                items = array
            } else {
                items = values
            }
            return RuleNodeCollection(nodes: items.map {
                RuleNode(storage: .json($0))
            })
        } catch let error as RuleExecutionError {
            if context.errorPolicy == .legadoCompatible { return RuleNodeCollection(nodes: []) }
            throw error
        } catch {
            if context.errorPolicy == .legadoCompatible { return RuleNodeCollection(nodes: []) }
            throw RuleExecutionError.invalidJSONPath(path)
        }
    }

    public func selectContext(
        jsonPath path: String,
        input: RuleExecutionInput,
        context: RuleExecutionContext
    ) throws -> RuleExecutionInput {
        do {
            let values = try evaluate(path, root: decode(input))
            guard !values.isEmpty else { throw RuleExecutionError.pathNotFound(path) }
            let value: JSONValue = values.count == 1 ? values[0] : .array(values)
            return RuleExecutionInput(node: RuleNode(storage: .json(value)))
        } catch let error as RuleExecutionError {
            if context.errorPolicy == .legadoCompatible { throw error }
            throw error
        } catch {
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

    private func decode(_ input: RuleExecutionInput) throws -> JSONValue {
        if let node = input.node {
            guard case let .json(value) = node.storage else {
                throw RuleExecutionError.unsupportedExecutionNode("JSONPath over an HTML node")
            }
            return value
        }
        if let nodes = input.nodes {
            let values = try nodes.nodes.map { node -> JSONValue in
                guard case let .json(value) = node.storage else {
                    throw RuleExecutionError.unsupportedExecutionNode("JSONPath over an HTML node")
                }
                return value
            }
            return .array(values)
        }
        return try decode(input.value)
    }

    private func evaluate(_ path: String, root: JSONValue) throws -> [JSONValue] {
        var parser = JSONPathParser(path)
        return try JSONPathEvaluator(root: root).evaluate(parser.parse())
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
