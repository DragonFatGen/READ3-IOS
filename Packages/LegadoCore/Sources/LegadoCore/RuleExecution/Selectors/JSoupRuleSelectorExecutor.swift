import Foundation
import SwiftSoup

public struct JSoupRuleSelectorExecutor: RuleSelectorExecutor {
    public init() {}

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
                    document: document
                )
            case .css:
                return try executeExplicitCSS(selector.value, document: document)
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
            return try executeHistoricalChain(childChain.map(\.value), document: document)
        } catch let error as RuleExecutionError {
            throw error
        } catch {
            throw RuleExecutionError.selectorExecutionFailed(String(describing: error))
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
        document: Element
    ) throws -> RuleValue {
        guard let extraction = chain.last else { return .none }
        var elements = Elements([document])
        for selection in chain.dropLast() {
            var next: [Element] = []
            for parent in elements {
                next.append(contentsOf: try selectHistorical(selection, from: parent).array())
            }
            elements = Elements(next)
        }
        return try extract(extraction, from: elements)
    }

    private func executeExplicitCSS(_ rule: String, document: Element) throws -> RuleValue {
        guard let delimiter = rule.lastIndex(of: "@") else {
            // Android's string extractor requires a final @ extraction field. Keeping
            // this explicit avoids silently treating a CSS query as historical syntax.
            throw RuleExecutionError.selectorExecutionFailed("@CSS requires a final @ extraction field.")
        }
        let query = String(rule[..<delimiter])
        let extraction = String(rule[rule.index(after: delimiter)...])
        return try extract(extraction, from: document.select(query))
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
                let value = try element.text()
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

    private func trimAndroidWhitespace(_ value: String) -> String {
        let withoutLeading = value.drop(while: { character in
            character.unicodeScalars.allSatisfy { $0.value <= 0x20 }
        })
        return String(withoutLeading.reversed().drop(while: { character in
            character.unicodeScalars.allSatisfy { $0.value <= 0x20 }
        }).reversed())
    }
}
