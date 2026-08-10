import Foundation

public enum RuleSyntaxError: Error, Equatable, Sendable {
    case unbalancedGroup(opening: Character, offset: Int)
    case unterminatedTemplate(offset: Int)
    case invalidOperatorSequence(operator: RuleOperator, offset: Int)
    case malformedRegex(String)
    case unsupportedPrefix(String)
    case emptyRequiredExpression
}

extension RuleSyntaxError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unbalancedGroup(opening, offset):
            return "Unbalanced \(opening) group at character offset \(offset)."
        case let .unterminatedTemplate(offset):
            return "Unterminated template at character offset \(offset)."
        case let .invalidOperatorSequence(op, offset):
            return "Empty expression around \(op.rawValue) at character offset \(offset)."
        case let .malformedRegex(pattern):
            return "Malformed regular expression: \(pattern)"
        case let .unsupportedPrefix(prefix):
            return "Unsupported rule prefix: \(prefix)"
        case .emptyRequiredExpression:
            return "A rule expression is required."
        }
    }
}
