import Foundation

public struct SetCookieParser: Sendable {
    public init() {}

    public func parse(_ header: String?, responseURL: URL, now: Date = Date()) -> [HTTPCookie] {
        guard let header, let host = responseURL.host?.lowercased() else { return [] }
        return splitCombinedHeader(header).compactMap { line in
            parseCookie(line, host: host, responseURL: responseURL, now: now)
        }
    }

    private func parseCookie(
        _ line: String,
        host: String,
        responseURL: URL,
        now: Date
    ) -> HTTPCookie? {
        let parts = line.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard let first = parts.first else { return nil }
        let pair = first.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard pair.count == 2 else { return nil }
        let name = pair[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        var domain = host
        var isHostOnly = true
        var path = defaultPath(for: responseURL)
        var expires: Date?
        var maxAge: Int?
        var secure = false
        var httpOnly = false

        for attribute in parts.dropFirst() {
            let item = attribute.trimmingCharacters(in: .whitespacesAndNewlines)
            let field = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = field[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = field.count == 2
                ? field[1].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            switch key {
            case "domain" where !value.isEmpty:
                let candidate = value.lowercased()
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                guard HTTPCookie.domainMatches(host: host, domain: candidate) else { return nil }
                domain = candidate
                isHostOnly = false
            case "path" where value.hasPrefix("/"):
                path = value
            case "expires":
                expires = parseDate(value)
            case "max-age":
                maxAge = Int(value)
            case "secure":
                secure = true
            case "httponly":
                httpOnly = true
            default:
                break
            }
        }

        if let maxAge {
            expires = maxAge <= 0 ? now.addingTimeInterval(-1) : now.addingTimeInterval(TimeInterval(maxAge))
        }
        return HTTPCookie(
            name: name,
            value: String(pair[1]),
            domain: domain,
            path: path,
            expires: expires,
            isSecure: secure,
            isHTTPOnly: httpOnly,
            isHostOnly: isHostOnly
        )
    }

    private func splitCombinedHeader(_ header: String) -> [String] {
        let normalized = header.replacingOccurrences(of: "\r\n", with: "\n")
        guard let expression = try? NSRegularExpression(
            pattern: #"(?:^|[\n,])\s*[!#$%&'*+\-.^_`|~0-9A-Za-z]+\s*="#
        ) else { return [normalized] }
        let range = NSRange(normalized.startIndex..., in: normalized)
        let matches = expression.matches(in: normalized, range: range)
        guard !matches.isEmpty else { return [] }
        return matches.indices.compactMap { index in
            guard var start = Range(matches[index].range, in: normalized)?.lowerBound else { return nil }
            if normalized[start] == "," || normalized[start] == "\n" {
                start = normalized.index(after: start)
            }
            let end: String.Index
            if index + 1 < matches.count {
                guard let nextRange = Range(matches[index + 1].range, in: normalized) else { return nil }
                end = nextRange.lowerBound
            } else {
                end = normalized.endIndex
            }
            var value = normalized[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasSuffix(",") { value.removeLast() }
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func defaultPath(for url: URL) -> String {
        let path = url.path
        guard path.hasPrefix("/"), path != "/",
              let slash = path.dropFirst().lastIndex(of: "/") else { return "/" }
        return String(path[..<slash])
    }

    private func parseDate(_ value: String) -> Date? {
        for format in [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEEE, dd-MMM-yy HH:mm:ss zzz",
            "EEE MMM d HH:mm:ss yyyy"
        ] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}
