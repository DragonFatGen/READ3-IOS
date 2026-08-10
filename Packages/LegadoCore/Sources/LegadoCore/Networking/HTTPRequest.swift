import Foundation

public enum HTTPRedirectPolicy: Codable, Equatable, Sendable {
    case follow(maximumHops: Int)
    case doNotFollow

    public static let legadoDefault = HTTPRedirectPolicy.follow(maximumHops: 20)
}

public enum HTTPBodyKind: String, Codable, Equatable, Sendable {
    case none
    case form
    case raw
}

public struct HTTPRequest: Equatable, Sendable {
    public let url: URL
    public let method: HTTPMethod
    public let headers: HTTPHeaders
    public let body: Data?
    public let bodyKind: HTTPBodyKind
    public let charset: String?
    public let redirectPolicy: HTTPRedirectPolicy
    public let cookies: [HTTPCookie]
    public let timeout: TimeInterval
    public let retryCount: Int
    public let options: RequestOptions

    public init(
        url: URL,
        method: HTTPMethod = .get,
        headers: HTTPHeaders = HTTPHeaders(),
        body: Data? = nil,
        bodyKind: HTTPBodyKind = .none,
        charset: String? = nil,
        redirectPolicy: HTTPRedirectPolicy = .legadoDefault,
        cookies: [HTTPCookie] = [],
        timeout: TimeInterval = 60,
        retryCount: Int = 0,
        options: RequestOptions = RequestOptions()
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.bodyKind = bodyKind
        self.charset = charset
        self.redirectPolicy = redirectPolicy
        self.cookies = cookies
        self.timeout = timeout
        self.retryCount = retryCount
        self.options = options
    }
}
