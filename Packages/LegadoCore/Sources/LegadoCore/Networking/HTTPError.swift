import Foundation

public enum HTTPError: Error, Equatable, Sendable {
    case invalidURL(String)
    case invalidRequestOptions(String)
    case invalidHeaders(String)
    case unsupportedMethod(String)
    case transportError(String)
    case invalidResponse
    case unsupportedCharset(String)
    case encodingFailed(String)
    case decodingFailed(String)
    case httpStatus(Int)
}

extension HTTPError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidURL(value): "Invalid URL: \(value)"
        case let .invalidRequestOptions(value): "Invalid request options: \(value)"
        case let .invalidHeaders(field): "Invalid HTTP headers in \(field)."
        case let .unsupportedMethod(method): "Unsupported HTTP method: \(method)"
        case let .transportError(message): "HTTP transport failed: \(message)"
        case .invalidResponse: "The HTTP response is invalid."
        case let .unsupportedCharset(charset): "Unsupported charset: \(charset)"
        case let .encodingFailed(charset): "Text encoding failed for charset: \(charset)"
        case let .decodingFailed(charset): "Text decoding failed for charset: \(charset)"
        case let .httpStatus(status): "HTTP request failed with status \(status)."
        }
    }
}
