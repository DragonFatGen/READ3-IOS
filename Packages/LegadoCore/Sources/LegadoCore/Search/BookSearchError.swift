import Foundation

public enum BookSearchError: Error, Sendable, Equatable {
    case searchNotSupported
    case requestBuildFailed(String)
    case networkFailed(String)
    case responseDecodeFailed(String)
    case bookListRuleFailed(String)
    case fieldRuleFailed(field: String, message: String)
    case requiredFieldMissing(String)
    case unsupportedStructuredRule(String)
    case unsupportedJavaScriptNetworkHost
}

extension BookSearchError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .searchNotSupported: "The book source has no executable search definition."
        case let .requestBuildFailed(message): "Search request construction failed: \(message)"
        case let .networkFailed(message): "Search request failed: \(message)"
        case let .responseDecodeFailed(message): "Search response decoding failed: \(message)"
        case let .bookListRuleFailed(message): "Book-list rule failed: \(message)"
        case let .fieldRuleFailed(field, message): "Search field \(field) failed: \(message)"
        case let .requiredFieldMissing(field): "Required search field is empty: \(field)"
        case let .unsupportedStructuredRule(rule): "The structured rule is unsupported: \(rule)"
        case .unsupportedJavaScriptNetworkHost:
            "This search requires the deferred production JavaScript network host."
        }
    }
}
