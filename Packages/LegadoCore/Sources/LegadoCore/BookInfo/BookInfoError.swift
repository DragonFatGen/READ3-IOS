import Foundation

public enum BookInfoError: Error, Sendable, Equatable {
    case requestBuildFailed(String)
    case networkFailed(String)
    case responseDecodeFailed(String)
    case initRuleFailed(String)
    case fieldRuleFailed(field: String, message: String)
    case unsupportedStructuredRule(String)
    case unsupportedJavaScriptNetworkHost
}

extension BookInfoError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .requestBuildFailed(message): "Book-info request construction failed: \(message)"
        case let .networkFailed(message): "Book-info request failed: \(message)"
        case let .responseDecodeFailed(message): "Book-info response decoding failed: \(message)"
        case let .initRuleFailed(message): "Book-info init rule failed: \(message)"
        case let .fieldRuleFailed(field, message): "Book-info field \(field) failed: \(message)"
        case let .unsupportedStructuredRule(rule): "The structured book-info rule is unsupported: \(rule)"
        case .unsupportedJavaScriptNetworkHost:
            "This book-info rule requires the deferred production JavaScript network host."
        }
    }
}
