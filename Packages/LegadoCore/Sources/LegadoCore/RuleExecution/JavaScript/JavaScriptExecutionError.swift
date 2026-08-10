import Foundation

public enum JavaScriptExecutionError: Error, Sendable, Equatable {
    case evaluationFailed(String)
    case resultConversionFailed(String)
    case resourceLimitExceeded(String)
}

extension JavaScriptExecutionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .evaluationFailed(message):
            "JavaScript execution failed: \(message)"
        case let .resultConversionFailed(message):
            "JavaScript result conversion failed: \(message)"
        case let .resourceLimitExceeded(message):
            "JavaScript resource limit exceeded: \(message)"
        }
    }
}
