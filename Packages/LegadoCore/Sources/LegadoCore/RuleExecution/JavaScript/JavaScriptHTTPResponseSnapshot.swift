import Foundation

public enum JavaScriptHTTPMethod: String, Codable, Sendable, Equatable {
    case get = "GET"
    case post = "POST"
    case head = "HEAD"
}

/// Immutable, platform-neutral reader view of the jsoup `Connection.Response`
/// returned by Android `java.get`, `java.post`, and `java.head`.
public struct JavaScriptHTTPResponseSnapshot: Codable, Sendable, Equatable {
    public let body: String
    public let statusCode: Int
    public let statusMessage: String
    public let headers: [String: String]
    public let cookies: [String: String]
    public let url: String
    public let contentType: String?
    public let charset: String?
    public let method: JavaScriptHTTPMethod

    public init(
        body: String,
        statusCode: Int,
        statusMessage: String = "",
        headers: [String: String] = [:],
        cookies: [String: String] = [:],
        url: String,
        contentType: String? = nil,
        charset: String? = nil,
        method: JavaScriptHTTPMethod
    ) {
        self.body = body
        self.statusCode = statusCode
        self.statusMessage = statusMessage
        self.headers = headers
        self.cookies = cookies
        self.url = url
        self.contentType = contentType
        self.charset = charset
        self.method = method
    }

    public func header(_ name: String) -> String? {
        let key = headers.keys.sorted {
            let folded = $0.caseInsensitiveCompare($1)
            return folded == .orderedSame ? $0 < $1 : folded == .orderedAscending
        }.first { $0.caseInsensitiveCompare(name) == .orderedSame }
        return key.flatMap { headers[$0] }
    }

    public func cookie(_ name: String) -> String? {
        cookies[name]
    }
}
