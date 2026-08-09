import Foundation

public enum RuleExecutionError: Error, Sendable, Equatable {
    case unsupportedExecutionNode(String)
    case invalidRegularExpression(String)
    case invalidCaptureGroup(Int)
    case selectorExecutionFailed(String)
    case invalidJSON(String)
    case invalidJSONPath(String)
    case pathNotFound(String)
    case unsupportedJSONPathFeature(String)
    case resultTypeMismatch(String)
}

extension RuleExecutionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unsupportedExecutionNode(node): "No executor is installed for \(node)."
        case let .invalidRegularExpression(pattern): "Invalid regular expression: \(pattern)"
        case let .invalidCaptureGroup(index): "Capture group $\(index) is unavailable."
        case let .selectorExecutionFailed(message): "Selector execution failed: \(message)"
        case let .invalidJSON(message): "Invalid JSON: \(message)"
        case let .invalidJSONPath(path): "Invalid JSONPath: \(path)"
        case let .pathNotFound(path): "JSONPath did not match: \(path)"
        case let .unsupportedJSONPathFeature(feature): "Unsupported JSONPath feature: \(feature)"
        case let .resultTypeMismatch(message): "JSONPath result type mismatch: \(message)"
        }
    }
}
