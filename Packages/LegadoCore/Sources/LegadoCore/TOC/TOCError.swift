import Foundation

public enum TOCError: Error, Sendable, Equatable {
    case requestBuildFailed(url: String, message: String)
    case networkFailed(url: String, message: String)
    case responseDecodeFailed(url: String, message: String)
    case chapterListRuleFailed(String)
    case nextPageRuleFailed(String)
    case chapterFieldRuleFailed(index: Int, field: String, message: String)
    case emptyChapterList
    case paginationLimitExceeded(Int)
    case unsupportedStructuredRule(String)
    case unsupportedJavaScriptNetworkHost
}

extension TOCError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .requestBuildFailed(url, message):
            "TOC request construction failed for \(url): \(message)"
        case let .networkFailed(url, message):
            "TOC request failed for \(url): \(message)"
        case let .responseDecodeFailed(url, message):
            "TOC response decoding failed for \(url): \(message)"
        case let .chapterListRuleFailed(message): "TOC chapter-list rule failed: \(message)"
        case let .nextPageRuleFailed(message): "TOC next-page rule failed: \(message)"
        case let .chapterFieldRuleFailed(index, field, message):
            "TOC chapter \(index) field \(field) failed: \(message)"
        case .emptyChapterList: "The TOC chapter list is empty."
        case let .paginationLimitExceeded(limit): "TOC pagination exceeded the safety limit of \(limit) pages."
        case let .unsupportedStructuredRule(rule): "The structured TOC rule is unsupported: \(rule)"
        case .unsupportedJavaScriptNetworkHost:
            "This TOC rule requires the deferred production JavaScript network host."
        }
    }
}
