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
        let charset = explicitCharset ?? contentTypeCharset ?? htmlMetaCharset ?? "utf-8"
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

    public var htmlMetaCharset: String? {
        let prefix = data.prefix(16_384)
        let probe = String(decoding: prefix, as: UTF8.self)
        let patterns = [
            #"(?i)<meta\b[^>]*\bcharset\s*=\s*[\"']?\s*([a-z0-9._:-]+)"#,
            #"(?i)<meta\b[^>]*\bcontent\s*=\s*[\"'][^\"']*charset\s*=\s*([a-z0-9._:-]+)"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(
                    in: probe,
                    range: NSRange(probe.startIndex..., in: probe)
                  ),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: probe) else { continue }
            return String(probe[range])
        }
        return nil
    }
}
