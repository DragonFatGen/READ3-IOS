import Foundation
import SwiftSoup

public struct JSoupRuleSelectorExecutor: RuleSelectorExecutor {
    public init() {}

    public func makeRootContext(
        input: RuleExecutionInput,
        contentIsJSON: Bool,
        context: RuleExecutionContext
    ) throws -> RuleExecutionInput {
        let root = try htmlRoots(input, parsingScalar: true)
        return RuleExecutionInput(node: RuleNode(storage: .html(
            HTMLRuleNode(owner: root.owner, element: root.elements[0])
        )))
    }

    public func execute(
        selector: SelectorRule,
        input: RuleValue,
        context: RuleExecutionContext
    ) throws -> RuleValue {
        do {
            let document = try SwiftSoup.parse(htmlInput(input))
            switch selector.type {
            case .legado:
                return try executeHistoricalChain(
                    [selector.value],
                    roots: [document]
                )
            case .css:
                return try executeExplicitCSS(selector.value, roots: [document])
            }
        } catch let error as RuleExecutionError {
            throw error
        } catch {
            throw RuleExecutionError.selectorExecutionFailed(String(describing: error))
        }
    }

    public func execute(
        selector: SelectorRule,
        input: RuleExecutionInput,
        context: RuleExecutionContext
    ) throws -> RuleValue {
        guard input.hasStructuredValue else {
            return try execute(selector: selector, input: input.value, context: context)
        }
        do {
            let root = try htmlRoots(input)
            return try root.owner.withLock {
                switch selector.type {
                case .legado:
                    return try executeHistoricalChain([selector.value], roots: root.elements)
                case .css:
                    return try executeExplicitCSS(selector.value, roots: root.elements)
                }
            }
        } catch let error as RuleExecutionError {
            throw error
        } catch {
            throw RuleExecutionError.selectorExecutionFailed(String(describing: error))
        }
    }

    public func execute(
        childChain: [SelectorRule],
        input: RuleValue,
        context: RuleExecutionContext
    ) throws -> RuleValue {
        guard childChain.allSatisfy({ $0.type == .legado }) else {
            throw RuleExecutionError.selectorExecutionFailed("A historical child chain contains a non-historical selector.")
        }
        do {
            let document = try SwiftSoup.parse(htmlInput(input))
            return try executeHistoricalChain(childChain.map(\.value), roots: [document])
        } catch let error as RuleExecutionError {
            throw error
        } catch {
            throw RuleExecutionError.selectorExecutionFailed(String(describing: error))
        }
    }

    public func execute(
        childChain: [SelectorRule],
        input: RuleExecutionInput,
        context: RuleExecutionContext
    ) throws -> RuleValue {
        guard input.hasStructuredValue else {
            return try execute(childChain: childChain, input: input.value, context: context)
        }
        guard childChain.allSatisfy({ $0.type == .legado }) else {
            throw RuleExecutionError.selectorExecutionFailed("A historical child chain contains a non-historical selector.")
        }
        let root = try htmlRoots(input)
        return try root.owner.withLock {
            try executeHistoricalChain(childChain.map(\.value), roots: root.elements)
        }
    }

    public func selectNodes(
        selector: SelectorRule,
        input: RuleExecutionInput,
        context: RuleExecutionContext
    ) throws -> RuleNodeCollection {
        let root = try htmlRoots(input, parsingScalar: true)
        return try root.owner.withLock {
            var selected: [Element] = []
            switch selector.type {
            case .legado:
                for element in root.elements {
                    selected.append(contentsOf: try selectHistorical(selector.value, from: element).array())
                }
            case .css:
                for element in root.elements {
                    selected.append(contentsOf: try element.select(selector.value).array())
                }
            }
            return RuleNodeCollection(nodes: selected.map {
                RuleNode(storage: .html(HTMLRuleNode(owner: root.owner, element: $0)))
            })
        }
    }

    public func selectNodes(
        childChain: [SelectorRule],
        input: RuleExecutionInput,
        context: RuleExecutionContext
    ) throws -> RuleNodeCollection {
        guard childChain.allSatisfy({ $0.type == .legado }) else {
            throw RuleExecutionError.selectorExecutionFailed("A historical child chain contains a non-historical selector.")
        }
        let root = try htmlRoots(input, parsingScalar: true)
        return try root.owner.withLock {
            var elements = Elements(root.elements)
            for selector in childChain {
                var next: [Element] = []
                for element in elements {
                    next.append(contentsOf: try selectHistorical(selector.value, from: element).array())
                }
                elements = Elements(next)
            }
            return RuleNodeCollection(nodes: elements.array().map {
                RuleNode(storage: .html(HTMLRuleNode(owner: root.owner, element: $0)))
            })
        }
    }

    public func execute(
        jsonPath: String,
        input: RuleValue,
        context: RuleExecutionContext
    ) throws -> RuleValue {
        throw RuleExecutionError.unsupportedExecutionNode("JSONPath")
    }

    public func execute(
        xpath: String,
        input: RuleValue,
        context: RuleExecutionContext
    ) throws -> RuleValue {
        throw RuleExecutionError.unsupportedExecutionNode("XPath")
    }

    private func executeHistoricalChain(
        _ chain: [String],
        roots: [Element]
    ) throws -> RuleValue {
        guard let extraction = chain.last else { return .none }
        var elements = Elements(roots)
        for selection in chain.dropLast() {
            var next: [Element] = []
            for parent in elements {
                next.append(contentsOf: try selectHistorical(selection, from: parent).array())
            }
            elements = Elements(next)
        }
        return try extract(extraction, from: elements)
    }

    private func executeExplicitCSS(_ rule: String, roots: [Element]) throws -> RuleValue {
        guard let delimiter = rule.lastIndex(of: "@") else {
            // Android's string extractor requires a final @ extraction field. Keeping
            // this explicit avoids silently treating a CSS query as historical syntax.
            throw RuleExecutionError.selectorExecutionFailed("@CSS requires a final @ extraction field.")
        }
        let query = String(rule[..<delimiter])
        let extraction = String(rule[rule.index(after: delimiter)...])
        var selected: [Element] = []
        for root in roots {
            selected.append(contentsOf: try root.select(query).array())
        }
        return try extract(extraction, from: Elements(selected))
    }

    private func selectHistorical(_ rawRule: String, from element: Element) throws -> Elements {
        let indexed = HistoricalSelectorIndex.parse(rawRule)
        let selected: Elements
        if indexed.selector.isEmpty || indexed.selector == "children" {
            selected = element.children()
        } else if indexed.selector.hasPrefix("class.") {
            selected = try element.getElementsByClass(String(indexed.selector.dropFirst(6)))
        } else if indexed.selector.hasPrefix("tag.") {
            selected = try element.getElementsByTag(String(indexed.selector.dropFirst(4)))
        } else if indexed.selector.hasPrefix("id.") {
            let match = try element.getElementById(String(indexed.selector.dropFirst(3)))
            selected = Elements(match.map { [$0] } ?? [])
        } else if indexed.selector.hasPrefix("text.") {
            selected = try element.getElementsContainingOwnText(String(indexed.selector.dropFirst(5)))
        } else {
            selected = try element.select(indexed.selector)
        }
        guard indexed.mode != .none else { return selected }
        let indexes = indexed.indexes(for: selected.count)
        switch indexed.mode {
        case .include:
            return Elements(indexes.map { selected[$0] })
        case .exclude:
            let excluded = Set(indexes)
            return Elements(selected.enumerated().compactMap { excluded.contains($0.offset) ? nil : $0.element })
        case .none:
            return selected
        }
    }

    private func extract(_ rule: String, from elements: Elements) throws -> RuleValue {
        switch rule {
        case "text":
            var values: [String] = []
            for element in elements {
                let value = try androidCompatibleText(element)
                if !value.isEmpty { values.append(value) }
            }
            return list(values)
        case "ownText":
            return list(elements.compactMap {
                let value = $0.ownText()
                return value.isEmpty ? nil : value
            })
        case "textNodes":
            return list(elements.compactMap { element in
                let values = element.textNodes().compactMap { node -> String? in
                    let value = trimAndroidWhitespace(node.text())
                    return value.isEmpty ? nil : value
                }
                return values.isEmpty ? nil : values.joined(separator: "\n")
            })
        case "html":
            _ = try elements.select("script").remove()
            _ = try elements.select("style").remove()
            let value = try elements.outerHtml()
            return value.isEmpty ? .none : .strings([value])
        case "all":
            let value = try elements.outerHtml()
            return .strings([value])
        default:
            var values: [String] = []
            for element in elements {
                let value = try element.attr(rule)
                if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !values.contains(value) {
                    values.append(value)
                }
            }
            return list(values)
        }
    }

    private func list(_ values: [String]) -> RuleValue {
        values.isEmpty ? .none : .strings(values)
    }

    private func htmlInput(_ input: RuleValue) -> String {
        switch input {
        case .none: ""
        case let .string(value): value
        case let .strings(values): "[" + values.joined(separator: ", ") + "]"
        }
    }

    private func htmlRoots(
        _ input: RuleExecutionInput,
        parsingScalar: Bool = false
    ) throws -> (owner: HTMLRuleNodeOwner, elements: [Element]) {
        let structured = input.structuredNodes
        if !structured.isEmpty {
            let htmlNodes = try structured.map { node -> HTMLRuleNode in
                guard case let .html(html) = node.storage else {
                    throw RuleExecutionError.unsupportedExecutionNode("JSoup over a JSON node")
                }
                return html
            }
            guard let first = htmlNodes.first,
                  htmlNodes.allSatisfy({ $0.owner === first.owner }) else {
                throw RuleExecutionError.unsupportedExecutionNode("JSoup nodes from different documents")
            }
            return (first.owner, htmlNodes.map(\.element))
        }
        if input.hasStructuredValue {
            if input.nodes?.isEmpty == true {
                let document = try SwiftSoup.parse("")
                return (HTMLRuleNodeOwner(retaining: [document]), [])
            } else {
                throw RuleExecutionError.unsupportedExecutionNode("JSoup over a JSON node")
            }
        }
        guard parsingScalar else {
            throw RuleExecutionError.selectorExecutionFailed("Missing HTML node input.")
        }
        let document = try SwiftSoup.parse(htmlInput(input.value))
        return (HTMLRuleNodeOwner(retaining: [document]), [document])
    }

    private func trimAndroidWhitespace(_ value: String) -> String {
        let withoutLeading = value.drop(while: { character in
            character.unicodeScalars.allSatisfy { $0.value <= 0x20 }
        })
        return String(withoutLeading.reversed().drop(while: { character in
            character.unicodeScalars.allSatisfy { $0.value <= 0x20 }
        }).reversed())
    }

    private func androidCompatibleText(_ element: Element) throws -> String {
        let visitor = AndroidTextVisitor()
        _ = try element.traverse(visitor)
        return visitor.value
    }
}

private final class AndroidTextVisitor: NodeVisitor {
    private var text = ""

    var value: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func head(_ node: Node, _ depth: Int) throws {
        if let textNode = node as? TextNode {
            appendNormalized(textNode.getWholeText())
        } else if let element = node as? Element,
                  element.isBlock() || element.tagNameNormal() == "br" {
            appendSpaceIfNeeded()
        }
    }

    func tail(_ node: Node, _ depth: Int) throws {
        guard let element = node as? Element,
              element.isBlock(),
              node.nextSibling() != nil else { return }
        appendSpaceIfNeeded()
    }

    private func appendNormalized(_ value: String) {
        for character in value {
            if character.isWhitespace {
                appendSpaceIfNeeded()
            } else {
                text.append(character)
            }
        }
    }

    private func appendSpaceIfNeeded() {
        guard !text.isEmpty, text.last != " " else { return }
        text.append(" ")
    }
}
