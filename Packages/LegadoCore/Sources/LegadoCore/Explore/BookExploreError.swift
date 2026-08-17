import Foundation

public enum BookExploreError: Error, Sendable, Equatable {
    case exploreNotSupported
    case requestBuildFailed(String)
    case networkFailed(String)
    case responseDecodeFailed(String)
    case bookListRuleFailed(String)
    case fieldRuleFailed(field: String, message: String)
    case unsupportedStructuredRule(String)
    case unsupportedJavaScriptNetworkHost
    case unsupportedWebView
}

extension BookExploreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .exploreNotSupported: "The book source has no executable explore definition."
        case let .requestBuildFailed(message): "Explore request construction failed: \(message)"
        case let .networkFailed(message): "Explore request failed: \(message)"
        case let .responseDecodeFailed(message): "Explore response decoding failed: \(message)"
        case let .bookListRuleFailed(message): "Explore book-list rule failed: \(message)"
        case let .fieldRuleFailed(field, message): "Explore field \(field) failed: \(message)"
        case let .unsupportedStructuredRule(rule): "The structured explore rule is unsupported: \(rule)"
        case .unsupportedJavaScriptNetworkHost:
            "This explore definition requires the deferred production JavaScript network host."
        case .unsupportedWebView:
            "WebView, webJs, and login-backed explore requests are not supported."
        }
    }
}
