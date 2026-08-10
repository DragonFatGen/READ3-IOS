public enum HTTPError: Error, Equatable, Sendable {
    case invalidURL(String)
    case invalidRequestOptions(String)
    case invalidHeaders(String)
    case unsupportedMethod(String)
    case transportError(String)
    case invalidResponse
    case unsupportedCharset(String)
    case decodingFailed(String)
    case httpStatus(Int)
}
