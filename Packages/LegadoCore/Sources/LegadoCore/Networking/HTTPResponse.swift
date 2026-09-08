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
        var candidates: [(charset: String, data: Data)] = []
        if let bom = byteOrderMark {
            candidates.append((bom.charset, data.dropFirst(bom.length)))
        }
        if let explicitCharset { candidates.append((explicitCharset, data)) }
        if let contentTypeCharset { candidates.append((contentTypeCharset, data)) }
        if let htmlMetaCharset { candidates.append((htmlMetaCharset, data)) }
        candidates.append(contentsOf: ["utf-8", "gb18030", "big5"].map { ($0, data) })

        var attempted: [String] = []
        var lossyFallback: String?
        var seen: Set<String> = []
        for candidate in candidates {
            let key = Self.normalizedCharset(candidate.charset)
            guard seen.insert(key).inserted else { continue }
            do {
                let value = try decoder.decode(candidate.data, charset: candidate.charset)
                if !value.contains("\u{FFFD}") { return value }
                if lossyFallback == nil { lossyFallback = value }
                attempted.append("\(candidate.charset) produced replacement characters")
            } catch {
                attempted.append("\(candidate.charset): \(error.localizedDescription)")
            }
        }
        if let lossyFallback { return lossyFallback }
        throw HTTPError.responseDecodingFailed(attempted.joined(separator: "; "))
    }

    var byteOrderMarkCharset: String? { byteOrderMark?.charset }

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

    private var byteOrderMark: (charset: String, length: Int)? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return ("utf-8", 3) }
        if data.starts(with: [0xFF, 0xFE]) { return ("utf-16le", 2) }
        if data.starts(with: [0xFE, 0xFF]) { return ("utf-16be", 2) }
        return nil
    }

    private static func normalizedCharset(_ charset: String) -> String {
        charset
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
    }
}
