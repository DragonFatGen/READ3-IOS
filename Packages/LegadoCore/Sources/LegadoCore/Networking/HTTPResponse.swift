import Foundation

public struct HTTPRedirect: Equatable, Sendable {
    public let from: URL
    public let to: URL
    public let statusCode: Int

    public init(from: URL, to: URL, statusCode: Int) {
        self.from = from
        self.to = to
        self.statusCode = statusCode
    }
}
public struct HTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let headers: HTTPHeaders
    public let data: Data
    public let finalURL: URL
    public let redirects: [HTTPRedirect]
    public let cookies: [HTTPCookie]

    public init(
        statusCode: Int,
        headers: HTTPHeaders = HTTPHeaders(),
        data: Data,
        finalURL: URL,
        redirects: [HTTPRedirect] = [],
        cookies: [HTTPCookie] = []
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.data = data
        self.finalURL = finalURL
        self.redirects = redirects
        self.cookies = cookies
    }

    public func text(
        explicitCharset: String? = nil,
        decoder: any TextDecoder = FoundationTextDecoder()
    ) throws -> String {
        let charset = explicitCharset ?? contentTypeCharset ?? "utf-8"
        return try decoder.decode(data, charset: charset)
    }

    public var contentTypeCharset: String? {
        guard let contentType = headers["Content-Type"] else { return nil }
        for part in contentType.split(separator: ";").dropFirst() {
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2,
                  pair[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare("charset") == .orderedSame else { continue }
            return pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }
}
