import Foundation

public struct RequestOptions: Equatable, Sendable {
    public var method: String?
    public var charset: String?
    public var headers: HTTPHeaders
    public var body: String?
    public var retry: Int
    public var type: String?
    public var webView: JSONValue?
    public var webJavaScript: String?
    public var javaScript: String?
    public var proxy: String?
    public var extraFields: [String: JSONValue]

    public init(
        method: String? = nil,
        charset: String? = nil,
        headers: HTTPHeaders = HTTPHeaders(),
        body: String? = nil,
        retry: Int = 0,
        type: String? = nil,
        webView: JSONValue? = nil,
        webJavaScript: String? = nil,
        javaScript: String? = nil,
        proxy: String? = nil,
        extraFields: [String: JSONValue] = [:]
    ) {
        self.method = method
        self.charset = charset
        self.headers = headers
        self.body = body
        self.retry = retry
        self.type = type
        self.webView = webView
        self.webJavaScript = webJavaScript
        self.javaScript = javaScript
        self.proxy = proxy
        self.extraFields = extraFields
    }

    public var requiresJavaScript: Bool {
        javaScript?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ||
            webJavaScript?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    public var requiresWebView: Bool {
        guard let webView else { return false }
        switch webView {
        case .null, .bool(false), .string(""): return false
        case .string(let value) where value.caseInsensitiveCompare("false") == .orderedSame: return false
        default: return true
        }
    }
}
