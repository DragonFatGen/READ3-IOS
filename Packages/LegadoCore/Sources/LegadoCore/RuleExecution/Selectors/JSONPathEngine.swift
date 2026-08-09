import Foundation

struct JSONPathQuery {
    let steps: [JSONPathStep]
}

enum JSONPathStep {
    case child([String])
    case wildcard
    case index([Int])
    case slice(start: Int?, end: Int?, step: Int?)
    case recursive([String]?)
    case filter(FilterExpression)
}

indirect enum FilterExpression {
    case literal(JSONValue)
    case path([FilterPathStep])
    case comparison(FilterOperator, FilterExpression, FilterExpression)
    case and(FilterExpression, FilterExpression)
    case or(FilterExpression, FilterExpression)
    case not(FilterExpression)
}

enum FilterPathStep: Equatable { case child(String), index(Int) }
enum FilterOperator: Equatable { case equal, notEqual, less, lessEqual, greater, greaterEqual }

struct JSONPathParser {
    private let characters: [Character]
    private var index = 0

    init(_ path: String) { characters = Array(path.trimmingCharacters(in: .whitespacesAndNewlines)) }

    mutating func parse() throws -> JSONPathQuery {
        guard !characters.isEmpty else { throw RuleExecutionError.invalidJSONPath("") }
        if peek() == "$" || peek() == "@" { index += 1 }
        var steps: [JSONPathStep] = []
        while index < characters.count {
            if consume("..") {
                if consume("*") { steps.append(.recursive(nil)) }
                else { steps.append(.recursive([try readName()])) }
            } else if consume(".") {
                if consume("*") { steps.append(.wildcard) }
                else { steps.append(.child([try readName()])) }
            } else if consume("[") {
                steps.append(try readBracket())
            } else if isNameCharacter(peek()) {
                steps.append(.child([try readName()]))
            } else {
                throw RuleExecutionError.invalidJSONPath(String(characters))
            }
        }
        return JSONPathQuery(steps: steps)
    }

    private mutating func readBracket() throws -> JSONPathStep {
        skipWhitespace()
        if consume("*") { try require("]"); return .wildcard }
        if consume("?(") {
            let body = try readBalancedFilter()
            try require("]")
            var parser = try FilterParser(body)
            return .filter(try parser.parse())
        }
        let content = try readUntilClosingBracket()
        if content.contains(":") {
            let fields = content.split(separator: ":", omittingEmptySubsequences: false)
            guard fields.count == 2 || fields.count == 3 else {
                throw RuleExecutionError.invalidJSONPath(String(characters))
            }
            guard fields.allSatisfy({ field in
                let text = field.trimmingCharacters(in: .whitespaces)
                return text.isEmpty || Int(text) != nil
            }) else {
                throw RuleExecutionError.invalidJSONPath(String(characters))
            }
            return .slice(
                start: parseOptionalInt(fields[0]),
                end: parseOptionalInt(fields[1]),
                step: fields.count == 3 ? parseOptionalInt(fields[2]) : nil
            )
        }
        let pieces = splitComma(content)
        if pieces.allSatisfy({ Int($0.trimmingCharacters(in: .whitespaces)) != nil }) {
            return .index(pieces.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
        }
        var names: [String] = []
        for piece in pieces {
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 2,
                  let first = trimmed.first, first == "'" || first == "\"",
                  trimmed.last == first else {
                throw RuleExecutionError.invalidJSONPath(String(characters))
            }
            names.append(unescape(String(trimmed.dropFirst().dropLast())))
        }
        return .child(names)
    }

    private mutating func readBalancedFilter() throws -> String {
        let start = index
        var depth = 1
        var quote: Character?
        var escaped = false
        while index < characters.count {
            let character = characters[index]
            if escaped { escaped = false; index += 1; continue }
            if character == "\\" { escaped = true; index += 1; continue }
            if let active = quote {
                if character == active { quote = nil }
                index += 1; continue
            }
            if character == "'" || character == "\"" { quote = character; index += 1; continue }
            if character == "(" { depth += 1 }
            if character == ")" {
                depth -= 1
                if depth == 0 {
                    let result = String(characters[start..<index])
                    index += 1
                    return result
                }
            }
            index += 1
        }
        throw RuleExecutionError.invalidJSONPath(String(characters))
    }

    private mutating func readUntilClosingBracket() throws -> String {
        let start = index
        var quote: Character?
        var escaped = false
        while index < characters.count {
            let character = characters[index]
            if escaped { escaped = false; index += 1; continue }
            if character == "\\" { escaped = true; index += 1; continue }
            if let active = quote {
                if character == active { quote = nil }
                index += 1; continue
            }
            if character == "'" || character == "\"" { quote = character; index += 1; continue }
            if character == "]" {
                let result = String(characters[start..<index])
                index += 1
                return result
            }
            index += 1
        }
        throw RuleExecutionError.invalidJSONPath(String(characters))
    }

    private mutating func readName() throws -> String {
        let start = index
        while index < characters.count, isNameCharacter(characters[index]) { index += 1 }
        guard index > start else { throw RuleExecutionError.invalidJSONPath(String(characters)) }
        return String(characters[start..<index])
    }

    private func isNameCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character != "." && character != "[" && character != "]" && !character.isWhitespace
    }

    private mutating func require(_ token: String) throws {
        skipWhitespace()
        guard consume(token) else { throw RuleExecutionError.invalidJSONPath(String(characters)) }
    }

    private mutating func consume(_ token: String) -> Bool {
        let value = Array(token)
        guard index + value.count <= characters.count,
              Array(characters[index..<(index + value.count)]) == value else { return false }
        index += value.count
        return true
    }

    private mutating func skipWhitespace() {
        while index < characters.count, characters[index].isWhitespace { index += 1 }
    }

    private func peek() -> Character? { index < characters.count ? characters[index] : nil }
    private func parseOptionalInt(_ value: Substring) -> Int? {
        let text = value.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : Int(text)
    }
    private func splitComma(_ value: String) -> [String] {
        var result: [String] = [], start = value.startIndex, index = start
        var quote: Character?, escaped = false
        while index < value.endIndex {
            let character = value[index]
            if escaped { escaped = false }
            else if character == "\\" { escaped = true }
            else if let active = quote { if character == active { quote = nil } }
            else if character == "'" || character == "\"" { quote = character }
            else if character == "," { result.append(String(value[start..<index])); start = value.index(after: index) }
            index = value.index(after: index)
        }
        result.append(String(value[start...]))
        return result
    }
    private func unescape(_ value: String) -> String {
        value.replacingOccurrences(of: #"\'"#, with: "'")
            .replacingOccurrences(of: #"\""#, with: "\"")
            .replacingOccurrences(of: #"\\"#, with: #"\"#)
    }
}

struct JSONPathEvaluator {
    let root: JSONValue

    func evaluate(_ query: JSONPathQuery) throws -> [JSONValue] {
        var current = [root]
        for step in query.steps {
            switch step {
            case let .child(names):
                current = current.flatMap { value in
                    guard case let .object(object) = value else { return [] }
                    return names.compactMap { object[$0] }
                }
            case .wildcard:
                current = current.flatMap(children)
            case let .index(indexes):
                current = current.flatMap { value in
                    guard case let .array(array) = value else { return [] }
                    return indexes.compactMap { index in
                        guard let index = resolved(index, count: array.count) else { return nil }
                        return array[index]
                    }
                }
            case let .slice(start, end, step):
                guard step != 0 else { throw RuleExecutionError.invalidJSONPath("slice step cannot be zero") }
                current = current.flatMap { slice($0, start: start, end: end, step: step ?? 1) }
            case let .recursive(names):
                current = current.flatMap { recursive($0, names: names) }
            case let .filter(expression):
                current = current.flatMap { value -> [JSONValue] in
                    guard case let .array(array) = value else { return [] }
                    return array.filter { truth(evaluateFilter(expression, current: $0)) }
                }
            }
        }
        return current
    }

    private func children(_ value: JSONValue) -> [JSONValue] {
        switch value {
        case let .array(values): values
        case let .object(values): values.keys.sorted().compactMap { values[$0] }
        default: []
        }
    }

    private func recursive(_ value: JSONValue, names: [String]?) -> [JSONValue] {
        var result: [JSONValue] = []
        switch value {
        case let .object(object):
            for key in object.keys.sorted() {
                guard let child = object[key] else { continue }
                if names == nil || names!.contains(key) { result.append(child) }
                result.append(contentsOf: recursive(child, names: names))
            }
        case let .array(array):
            for child in array {
                if names == nil { result.append(child) }
                result.append(contentsOf: recursive(child, names: names))
            }
        default: break
        }
        return result
    }

    private func slice(_ value: JSONValue, start: Int?, end: Int?, step: Int) -> [JSONValue] {
        guard case let .array(array) = value, !array.isEmpty else { return [] }
        var result: [JSONValue] = []
        if step > 0 {
            var index = normalizedBound(start ?? 0, count: array.count, positive: true)
            let limit = normalizedBound(end ?? array.count, count: array.count, positive: true)
            while index < limit { if array.indices.contains(index) { result.append(array[index]) }; index += step }
        } else {
            var index = start.map { normalizedBound($0, count: array.count, positive: false) } ?? (array.count - 1)
            let limit = end.map { normalizedBound($0, count: array.count, positive: false) } ?? -1
            while index > limit { if array.indices.contains(index) { result.append(array[index]) }; index += step }
        }
        return result
    }

    private func normalizedBound(_ value: Int, count: Int, positive: Bool) -> Int {
        let adjusted = value < 0 ? count + value : value
        return min(max(adjusted, positive ? 0 : -1), count)
    }

    private func resolved(_ index: Int, count: Int) -> Int? {
        let value = index < 0 ? count + index : index
        return value >= 0 && value < count ? value : nil
    }

    private func evaluateFilter(_ expression: FilterExpression, current: JSONValue) -> JSONValue {
        switch expression {
        case let .literal(value): value
        case let .path(steps):
            var values = [current]
            for step in steps {
                switch step {
                case let .child(name): values = values.compactMap { if case let .object(o) = $0 { o[name] } else { nil } }
                case let .index(index): values = values.compactMap { value in
                    guard case let .array(a) = value, let i = resolved(index, count: a.count) else { return nil }
                    return a[i]
                }
                }
            }
            return values.first ?? .null
        case let .comparison(op, lhs, rhs): .bool(compare(op, evaluateFilter(lhs, current: current), evaluateFilter(rhs, current: current)))
        case let .and(lhs, rhs): .bool(truth(evaluateFilter(lhs, current: current)) && truth(evaluateFilter(rhs, current: current)))
        case let .or(lhs, rhs): .bool(truth(evaluateFilter(lhs, current: current)) || truth(evaluateFilter(rhs, current: current)))
        case let .not(value): .bool(!truth(evaluateFilter(value, current: current)))
        }
    }

    private func truth(_ value: JSONValue) -> Bool {
        switch value { case .null: false; case let .bool(v): v; default: true }
    }
    private func compare(_ op: FilterOperator, _ lhs: JSONValue, _ rhs: JSONValue) -> Bool {
        if let leftNumber = scalar(lhs), let rightNumber = scalar(rhs) {
            switch op {
            case .equal: return leftNumber == rightNumber
            case .notEqual: return leftNumber != rightNumber
            case .less: return leftNumber < rightNumber
            case .lessEqual: return leftNumber <= rightNumber
            case .greater: return leftNumber > rightNumber
            case .greaterEqual: return leftNumber >= rightNumber
            }
        }
        if op == .equal { return lhs == rhs }
        if op == .notEqual { return lhs != rhs }
        let l = scalar(lhs), r = scalar(rhs)
        guard let l, let r else { return false }
        switch op { case .less: l < r; case .lessEqual: l <= r; case .greater: l > r; case .greaterEqual: l >= r; default: false }
    }
    private func scalar(_ value: JSONValue) -> Double? {
        switch value { case let .integer(v): Double(v); case let .number(v): v; case let .string(v): Double(v); default: nil }
    }
}

private struct FilterParser {
    private let tokens: [FilterToken]
    private var index = 0
    init(_ value: String) throws { tokens = try FilterLexer(value).scan() }
    mutating func parse() throws -> FilterExpression {
        let expression = try parseOr()
        guard index == tokens.count else { throw RuleExecutionError.invalidJSONPath("invalid filter") }
        return expression
    }
    private mutating func parseOr() throws -> FilterExpression {
        var value = try parseAnd()
        while consume(.or) { value = .or(value, try parseAnd()) }
        return value
    }
    private mutating func parseAnd() throws -> FilterExpression {
        var value = try parseComparison()
        while consume(.and) { value = .and(value, try parseComparison()) }
        return value
    }
    private mutating func parseComparison() throws -> FilterExpression {
        var value = try parsePrimary()
        if let operation = comparison() { value = .comparison(operation, value, try parsePrimary()) }
        return value
    }
    private mutating func parsePrimary() throws -> FilterExpression {
        if consume(.not) { return .not(try parsePrimary()) }
        if consume(.leftParen) { let value = try parseOr(); guard consume(.rightParen) else { throw RuleExecutionError.invalidJSONPath("unbalanced filter") }; return value }
        guard index < tokens.count else { throw RuleExecutionError.invalidJSONPath("missing filter operand") }
        defer { index += 1 }
        switch tokens[index] {
        case let .literal(value): return .literal(value)
        case let .path(steps): return .path(steps)
        default: throw RuleExecutionError.invalidJSONPath("invalid filter operand")
        }
    }
    private mutating func comparison() -> FilterOperator? {
        guard index < tokens.count else { return nil }
        let value: FilterOperator?
        switch tokens[index] { case .equal: value = .equal; case .notEqual: value = .notEqual; case .less: value = .less; case .lessEqual: value = .lessEqual; case .greater: value = .greater; case .greaterEqual: value = .greaterEqual; default: value = nil }
        if value != nil { index += 1 }; return value
    }
    private mutating func consume(_ token: FilterToken) -> Bool {
        guard index < tokens.count, tokens[index] == token else { return false }; index += 1; return true
    }
}

private enum FilterToken: Equatable {
    case path([FilterPathStep]), literal(JSONValue), equal, notEqual, less, lessEqual, greater, greaterEqual, and, or, not, leftParen, rightParen
}

private struct FilterLexer {
    let characters: [Character]
    init(_ value: String) { characters = Array(value) }
    func scan() throws -> [FilterToken] {
        var result: [FilterToken] = [], index = 0
        while index < characters.count {
            if characters[index].isWhitespace { index += 1; continue }
            func matches(_ text: String) -> Bool { let v=Array(text); return index+v.count <= characters.count && Array(characters[index..<(index+v.count)]) == v }
            if matches("&&") { result.append(.and); index += 2 }
            else if matches("||") { result.append(.or); index += 2 }
            else if matches("==") { result.append(.equal); index += 2 }
            else if matches("!=") { result.append(.notEqual); index += 2 }
            else if matches("<=") { result.append(.lessEqual); index += 2 }
            else if matches(">=") { result.append(.greaterEqual); index += 2 }
            else if matches("=~") {
                throw RuleExecutionError.unsupportedJSONPathFeature("filter regular expressions")
            }
            else if characters[index] == "<" { result.append(.less); index += 1 }
            else if characters[index] == ">" { result.append(.greater); index += 1 }
            else if characters[index] == "!" { result.append(.not); index += 1 }
            else if characters[index] == "(" { result.append(.leftParen); index += 1 }
            else if characters[index] == ")" { result.append(.rightParen); index += 1 }
            else if characters[index] == "=" || characters[index] == "&" || characters[index] == "|" {
                throw RuleExecutionError.unsupportedJSONPathFeature("filter operator")
            }
            else if characters[index] == "@" || characters[index] == "$" {
                let parsed = try readPath(from: index); result.append(.path(parsed.steps)); index = parsed.end
            } else if characters[index] == "'" || characters[index] == "\"" {
                let parsed = try readString(from: index); result.append(.literal(.string(parsed.value))); index = parsed.end
            } else {
                let start = index
                while index < characters.count, !characters[index].isWhitespace, !"()!<>=&|".contains(characters[index]) { index += 1 }
                let text = String(characters[start..<index])
                if text == "true" { result.append(.literal(.bool(true))) }
                else if text == "false" { result.append(.literal(.bool(false))) }
                else if text == "null" { result.append(.literal(.null)) }
                else if let integer = Int64(text) { result.append(.literal(.integer(integer))) }
                else if let number = Double(text) { result.append(.literal(.number(number))) }
                else { throw RuleExecutionError.unsupportedJSONPathFeature("filter token \(text)") }
            }
        }
        return result
    }
    private func readPath(from start: Int) throws -> (steps: [FilterPathStep], end: Int) {
        var index = start + 1, steps: [FilterPathStep] = []
        while index < characters.count {
            if characters[index] == "." {
                index += 1; let nameStart = index
                while index < characters.count, !".[]() !<>=&|".contains(characters[index]) { index += 1 }
                guard index > nameStart else { throw RuleExecutionError.invalidJSONPath("empty filter property") }
                steps.append(.child(String(characters[nameStart..<index])))
            } else if characters[index] == "[" {
                index += 1; let numberStart = index
                while index < characters.count, characters[index] != "]" { index += 1 }
                guard index < characters.count, let number = Int(String(characters[numberStart..<index])) else { throw RuleExecutionError.invalidJSONPath("invalid filter index") }
                steps.append(.index(number)); index += 1
            } else { break }
        }
        return (steps, index)
    }
    private func readString(from start: Int) throws -> (value: String, end: Int) {
        let quote = characters[start]; var index = start + 1, value = "", escaped = false
        while index < characters.count {
            let character = characters[index]
            if escaped { value.append(character); escaped = false }
            else if character == "\\" { escaped = true }
            else if character == quote { return (value, index + 1) }
            else { value.append(character) }
            index += 1
        }
        throw RuleExecutionError.invalidJSONPath("unterminated filter string")
    }
}
