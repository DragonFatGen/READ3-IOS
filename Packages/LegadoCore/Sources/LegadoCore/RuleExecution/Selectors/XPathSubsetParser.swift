import Foundation

enum XPathExpression {
    case path(XPathPath)
    case count(XPathPath)
    case contains(XPathOperand, XPathOperand)
    case startsWith(XPathOperand, XPathOperand)
}

struct XPathPath {
    let beginsAtRoot: Bool
    let steps: [XPathStep]
}

struct XPathStep {
    enum Axis { case child, descendant }
    enum Test {
        case element(String)
        case text
        case node
        case attribute(String)
        case allText
        case html
        case outerHTML
        case current
        case parent
    }

    let axis: Axis
    let test: Test
    let predicates: [String]
}

enum XPathOperand {
    case literal(String)
    case path(XPathPath)
}

struct XPathSubsetParser {
    private let source: String

    init(_ source: String) {
        self.source = source.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func parse() throws -> XPathExpression {
        guard !source.isEmpty else { throw RuleExecutionError.invalidXPath(source) }
        if let call = try topLevelFunction(source) {
            switch call.name {
            case "count":
                guard call.arguments.count == 1 else { throw RuleExecutionError.invalidXPath(source) }
                return .count(try parsePath(call.arguments[0]))
            case "contains":
                guard call.arguments.count == 2 else { throw RuleExecutionError.invalidXPath(source) }
                return .contains(try parseOperand(call.arguments[0]), try parseOperand(call.arguments[1]))
            case "starts-with":
                guard call.arguments.count == 2 else { throw RuleExecutionError.invalidXPath(source) }
                return .startsWith(try parseOperand(call.arguments[0]), try parseOperand(call.arguments[1]))
            case "string", "normalize-space":
                throw RuleExecutionError.unsupportedXPathFeature("\(call.name)()")
            default:
                throw RuleExecutionError.unsupportedXPathFeature("\(call.name)()")
            }
        }
        return .path(try parsePath(source))
    }

    private func parseOperand(_ raw: String) throws -> XPathOperand {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count >= 2, let quote = value.first,
           (quote == "'" || quote == "\""), value.last == quote {
            return .literal(String(value.dropFirst().dropLast()))
        }
        return .path(try parsePath(value))
    }

    private func parsePath(_ raw: String) throws -> XPathPath {
        let characters = Array(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !characters.isEmpty else { throw RuleExecutionError.invalidXPath(raw) }
        var index = 0
        var beginsAtRoot = false
        var nextAxis = XPathStep.Axis.child
        if matches("//", at: index, in: characters) {
            beginsAtRoot = true
            nextAxis = .descendant
            index += 2
        } else if characters[index] == "/" {
            beginsAtRoot = true
            index += 1
        }
        var steps: [XPathStep] = []
        while index < characters.count {
            let start = index
            var bracketDepth = 0
            var parenthesisDepth = 0
            var quote: Character?
            while index < characters.count {
                let character = characters[index]
                if let active = quote {
                    if character == active { quote = nil }
                    index += 1
                    continue
                }
                if character == "'" || character == "\"" { quote = character; index += 1; continue }
                if character == "[" { bracketDepth += 1 }
                else if character == "]" { bracketDepth -= 1; if bracketDepth < 0 { throw RuleExecutionError.invalidXPath(raw) } }
                else if character == "(" { parenthesisDepth += 1 }
                else if character == ")" { parenthesisDepth -= 1; if parenthesisDepth < 0 { throw RuleExecutionError.invalidXPath(raw) } }
                if bracketDepth == 0, parenthesisDepth == 0, character == "/" { break }
                index += 1
            }
            guard bracketDepth == 0, parenthesisDepth == 0, quote == nil, index > start else {
                throw RuleExecutionError.invalidXPath(raw)
            }
            steps.append(try parseStep(String(characters[start..<index]), axis: nextAxis))
            if index < characters.count {
                if matches("//", at: index, in: characters) { nextAxis = .descendant; index += 2 }
                else { nextAxis = .child; index += 1 }
                if index == characters.count { throw RuleExecutionError.invalidXPath(raw) }
            }
        }
        guard !steps.isEmpty else { throw RuleExecutionError.invalidXPath(raw) }
        return XPathPath(beginsAtRoot: beginsAtRoot, steps: steps)
    }

    private func parseStep(_ raw: String, axis: XPathStep.Axis) throws -> XPathStep {
        let characters = Array(raw)
        var testEnd = characters.count
        var quote: Character?
        var parenthesisDepth = 0
        for index in characters.indices {
            let character = characters[index]
            if let active = quote { if character == active { quote = nil }; continue }
            if character == "'" || character == "\"" { quote = character; continue }
            if character == "(" { parenthesisDepth += 1 }
            else if character == ")" { parenthesisDepth -= 1 }
            else if character == "[", parenthesisDepth == 0 { testEnd = index; break }
        }
        let testText = String(characters[..<testEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        let predicates = try parsePredicates(String(characters[testEnd...]))
        let test: XPathStep.Test
        switch testText {
        case ".": test = .current
        case "..": test = .parent
        case "text()": test = .text
        case "node()": test = .node
        case "allText()": test = .allText
        case "html()": test = .html
        case "outerHtml()": test = .outerHTML
        default:
            if testText.hasPrefix("@") {
                let name = String(testText.dropFirst())
                guard !name.isEmpty else { throw RuleExecutionError.invalidXPath(raw) }
                test = .attribute(name)
            } else if testText.hasPrefix("attribute::") {
                let name = String(testText.dropFirst("attribute::".count))
                guard !name.isEmpty else { throw RuleExecutionError.invalidXPath(raw) }
                test = .attribute(name)
            } else if testText.contains("::") {
                throw RuleExecutionError.unsupportedXPathFeature(testText)
            } else if testText.hasSuffix("()") {
                throw RuleExecutionError.unsupportedXPathFeature(testText)
            } else if !testText.isEmpty {
                test = .element(testText)
            } else {
                throw RuleExecutionError.invalidXPath(raw)
            }
        }
        if !predicates.isEmpty {
            switch test {
            case .element, .text: break
            default: throw RuleExecutionError.unsupportedXPathFeature("predicate on \(testText)")
            }
        }
        return XPathStep(axis: axis, test: test, predicates: predicates)
    }

    private func parsePredicates(_ raw: String) throws -> [String] {
        let characters = Array(raw)
        var result: [String] = []
        var index = 0
        while index < characters.count {
            while index < characters.count, characters[index].isWhitespace { index += 1 }
            guard index < characters.count else { break }
            guard characters[index] == "[" else { throw RuleExecutionError.invalidXPath(raw) }
            let start = index + 1
            index += 1
            var depth = 1
            var quote: Character?
            while index < characters.count, depth > 0 {
                let character = characters[index]
                if let active = quote { if character == active { quote = nil }; index += 1; continue }
                if character == "'" || character == "\"" { quote = character; index += 1; continue }
                if character == "[" { depth += 1 }
                else if character == "]" { depth -= 1 }
                index += 1
            }
            guard depth == 0 else { throw RuleExecutionError.invalidXPath(raw) }
            let predicate = String(characters[start..<(index - 1)]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !predicate.isEmpty else { throw RuleExecutionError.invalidXPath(raw) }
            result.append(predicate)
        }
        return result
    }

    private func topLevelFunction(_ raw: String) throws -> (name: String, arguments: [String])? {
        guard let open = raw.firstIndex(of: "("), raw.last == ")" else { return nil }
        let name = String(raw[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/") else { return nil }
        let bodyStart = raw.index(after: open)
        let body = String(raw[bodyStart..<raw.index(before: raw.endIndex)])
        return (name, try splitArguments(body))
    }

    private func splitArguments(_ raw: String) throws -> [String] {
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        let characters = Array(raw)
        var result: [String] = []
        var start = 0
        var depth = 0
        var brackets = 0
        var quote: Character?
        for index in characters.indices {
            let character = characters[index]
            if let active = quote { if character == active { quote = nil }; continue }
            if character == "'" || character == "\"" { quote = character; continue }
            if character == "(" { depth += 1 }
            else if character == ")" { depth -= 1 }
            else if character == "[" { brackets += 1 }
            else if character == "]" { brackets -= 1 }
            else if character == ",", depth == 0, brackets == 0 {
                result.append(String(characters[start..<index])); start = index + 1
            }
            if depth < 0 || brackets < 0 { throw RuleExecutionError.invalidXPath(raw) }
        }
        guard depth == 0, brackets == 0, quote == nil else { throw RuleExecutionError.invalidXPath(raw) }
        result.append(String(characters[start...]))
        return result
    }

    private func matches(_ token: String, at index: Int, in characters: [Character]) -> Bool {
        let token = Array(token)
        return index + token.count <= characters.count && Array(characters[index..<(index + token.count)]) == token
    }
}
