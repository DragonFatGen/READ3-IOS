import Foundation

public enum RuleExecutionError: Error, Sendable, Equatable {
    case unsupportedExecutionNode(String)
    case invalidRegularExpression(String)
    case invalidCaptureGroup(Int)
}

extension RuleExecutionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unsupportedExecutionNode(node): "No executor is installed for \(node)."
        case let .invalidRegularExpression(pattern): "Invalid regular expression: \(pattern)"
        case let .invalidCaptureGroup(index): "Capture group $\(index) is unavailable."
        }
    }
}
