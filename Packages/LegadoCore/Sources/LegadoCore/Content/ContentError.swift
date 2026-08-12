import Foundation

public enum ContentError: Error, Sendable, Equatable {
    case requestBuildFailed(url: String, message: String)
    case networkFailed(url: String, message: String)
    case responseDecodeFailed(url: String, message: String)
    case contentRuleFailed(String)
    case nextPageRuleFailed(String)
    case purificationRuleFailed(String)
    case emptyContent
    case paginationLimitExceeded(Int)
    case unsupportedStructuredRule(String)
    case unsupportedJavaScriptNetworkHost
}

extension ContentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .requestBuildFailed(url, message):
            "Content request construction failed for \(url): \(message)"
        case let .networkFailed(url, message):
            "Content request failed for \(url): \(message)"
        case let .responseDecodeFailed(url, message):
            "Content response decoding failed for \(url): \(message)"
        case let .contentRuleFailed(message):
            "Content rule failed: \(message)"
        case let .nextPageRuleFailed(message):
            "Content next-page rule failed: \(message)"
        case let .purificationRuleFailed(message):
            "Content purification rule failed: \(message)"
        case .emptyContent:
            "The chapter content is empty."
        case let .paginationLimitExceeded(limit):
            "Content pagination exceeded the safety limit of \(limit) pages."
        case let .unsupportedStructuredRule(rule):
            "The structured content rule is unsupported: \(rule)"
        case .unsupportedJavaScriptNetworkHost:
            "This content rule requires the deferred production JavaScript network host."
        }
    }
}
