import Foundation

public enum BookInfoError: Error, Sendable, Equatable {
    case bookInfoNotSupported
    case emptyBookURL
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
        case .bookInfoNotSupported: "The book source has no BookInfo rule definition."
        case .emptyBookURL: "The selected book has no detail URL."
        case let .requestBuildFailed(message): "BookInfo request construction failed: \(message)"
        case let .networkFailed(message): "BookInfo request failed: \(message)"
        case let .responseDecodeFailed(message): "BookInfo response decoding failed: \(message)"
        case let .initRuleFailed(message): "BookInfo init rule failed: \(message)"
        case let .fieldRuleFailed(field, message): "BookInfo field \(field) failed: \(message)"
        case let .unsupportedStructuredRule(rule): "The structured BookInfo rule is unsupported: \(rule)"
        case .unsupportedJavaScriptNetworkHost:
            "This BookInfo rule requires the deferred production JavaScript network host."
        }
    }
}
