import Foundation

public struct RequestBuildContext: Equatable, Sendable {
    public var keyword: String?
    public var page: Int?
    public var pageSize: Int?
    public var sourceURL: String?
    public var baseURL: String?
    public var sourceVariables: [String: String]
    public var sourceIdentifier: String?
    public var defaultUserAgent: String
    public var timeout: TimeInterval
    public var redirectPolicy: HTTPRedirectPolicy
    public var errorPolicy: RuleParseContext.ErrorPolicy

    public init(
        keyword: String? = nil,
        page: Int? = nil,
        pageSize: Int? = nil,
        sourceURL: String? = nil,
        baseURL: String? = nil,
        sourceVariables: [String: String] = [:],
        sourceIdentifier: String? = nil,
        defaultUserAgent: String = "Legado/3.0",
        timeout: TimeInterval = 60,
        redirectPolicy: HTTPRedirectPolicy = .legadoDefault,
        errorPolicy: RuleParseContext.ErrorPolicy = .legadoCompatible
    ) {
        self.keyword = keyword
        self.page = page
        self.pageSize = pageSize
        self.sourceURL = sourceURL
        self.baseURL = baseURL
        self.sourceVariables = sourceVariables
        self.sourceIdentifier = sourceIdentifier
        self.defaultUserAgent = defaultUserAgent
        self.timeout = timeout
        self.redirectPolicy = redirectPolicy
        self.errorPolicy = errorPolicy
    }
}

public struct RequestBuilder: Sendable {
    private let cookieStore: (any HTTPCookieStore)?

    public init(cookieStore: (any HTTPCookieStore)? = nil) {
        self.cookieStore = cookieStore
    }

    public func build(
        _ legadoURL: String,
        source: BookSource,
        context: RequestBuildContext = RequestBuildContext()
    ) async throws -> HTTPRequest {
        var resolvedContext = context
        if resolvedContext.sourceURL == nil { resolvedContext.sourceURL = source.bookSourceUrl }
        if resolvedContext.baseURL == nil { resolvedContext.baseURL = source.bookSourceUrl }
        if resolvedContext.sourceIdentifier == nil { resolvedContext.sourceIdentifier = source.bookSourceUrl }
        return try await build(legadoURL, sourceHeader: source.header, context: resolvedContext)
    }

    public func build(
        _ legadoURL: String,
        sourceHeader: String? = nil,
        context: RequestBuildContext = RequestBuildContext()
    ) async throws -> HTTPRequest {
        let rendered = try render(legadoURL, context: context)
        let parts = splitOptions(rendered)
        let options = try parseOptions(parts.options, policy: context.errorPolicy)
        let method = try parseMethod(options.method, policy: context.errorPolicy)

        var headers = HTTPHeaders(["User-Agent": context.defaultUserAgent])
        let sourceHeaders: HTTPHeaders
        do {
            sourceHeaders = try parseHeaders(sourceHeader, field: "source header")
        } catch {
            if context.errorPolicy == .strict { throw error }
            sourceHeaders = HTTPHeaders()
        }
        headers.merge(sourceHeaders)
        headers.merge(options.headers)

        var effectiveOptions = options
        if let proxy = headers["proxy"] {
            effectiveOptions.proxy = proxy
            headers["proxy"] = nil
        }

        let resolvedURL = if method == .get {
            try resolveGETURL(parts.url, baseURL: context.baseURL, charset: options.charset)
        } else {
            resolveURL(parts.url, baseURL: context.baseURL)
        }
        guard let resolvedURL else {
            throw HTTPError.invalidURL(parts.url)
        }
        let url = resolvedURL
        let cookies = await cookieStore?.cookies(
            for: url,
            sourceIdentifier: context.sourceIdentifier
        ) ?? []
        mergeCookies(cookies, into: &headers)

        let bodyResult = try makeBody(
            options.body,
            method: method,
            charset: options.charset,
            headers: &headers
        )
        return HTTPRequest(
            url: url,
            method: method,
            headers: headers,
            body: bodyResult.data,
            bodyKind: bodyResult.kind,
            charset: options.charset,
            redirectPolicy: context.redirectPolicy,
            cookies: cookies,
            timeout: context.timeout,
            retryCount: max(0, options.retry),
            options: effectiveOptions
        )
    }

    private func render(_ value: String, context: RequestBuildContext) throws -> String {
        var variables = context.sourceVariables
        if let keyword = context.keyword {
            variables["key"] = keyword
            variables["keyword"] = keyword
        }
        if let page = context.page { variables["page"] = String(page) }
        if let pageSize = context.pageSize { variables["pageSize"] = String(pageSize) }
        if let sourceURL = context.sourceURL { variables["sourceUrl"] = sourceURL }
        if let baseURL = context.baseURL { variables["baseUrl"] = baseURL }

        var normalized = value
        for key in variables.keys.sorted(by: { $0.count > $1.count }) {
            normalized = normalized.replacingOccurrences(of: "{{\(key)}}", with: "@get:{\(key)}")
        }
        guard normalized.contains("{{") ||
                normalized.range(of: "@get:{", options: .caseInsensitive) != nil ||
                normalized.range(of: "@put:{", options: .caseInsensitive) != nil else {
            return replacePageAlternatives(normalized, page: context.page)
        }
        var executionContext = RuleExecutionContext(
            baseUrl: context.baseURL ?? "",
            sourceVariables: context.sourceVariables,
            temporaryVariables: variables,
            errorPolicy: context.errorPolicy
        )
        let expression = try RuleParser().parse(normalized, context: RuleParseContext(errorPolicy: context.errorPolicy))
        let rendered = try RuleExecutor().execute(
            expression,
            input: RuleExecutionInput(.none),
            context: &executionContext
        ).value.stringValue
        return replacePageAlternatives(rendered, page: context.page)
    }

    private func replacePageAlternatives(_ value: String, page: Int?) -> String {
        guard let page else { return value }
        var result = value
        while let open = result.firstIndex(of: "<"),
              let close = result[open...].firstIndex(of: ">") {
            let choices = result[result.index(after: open)..<close]
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard !choices.isEmpty else { break }
            let index = min(max(page - 1, 0), choices.count - 1)
            result.replaceSubrange(open...close, with: choices[index])
        }
        return result
    }

    private func splitOptions(_ value: String) -> (url: String, options: String?) {
        var index = value.startIndex
        while index < value.endIndex {
            guard value[index] == "," else {
                index = value.index(after: index)
                continue
            }
            var next = value.index(after: index)
            while next < value.endIndex, value[next].isWhitespace { next = value.index(after: next) }
            if next < value.endIndex, value[next] == "{" {
                return (String(value[..<index]), String(value[next...]))
            }
            index = value.index(after: index)
        }
        return (value, nil)
    }

    private func parseOptions(
        _ text: String?,
        policy: RuleParseContext.ErrorPolicy
    ) throws -> RequestOptions {
        guard let text else { return RequestOptions() }
        do {
            let json = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
            guard case let .object(values) = json else { throw HTTPError.invalidRequestOptions(text) }
            return try requestOptions(values, policy: policy)
        } catch let error as HTTPError {
            if policy == .strict { throw error }
            return RequestOptions()
        } catch {
            if policy == .strict { throw HTTPError.invalidRequestOptions(text) }
            return RequestOptions()
        }
    }

    private func requestOptions(
        _ values: [String: JSONValue],
        policy: RuleParseContext.ErrorPolicy
    ) throws -> RequestOptions {
        var remaining = values
        let method = remaining.removeValue(forKey: "method")?.stringValue
        let charset = remaining.removeValue(forKey: "charset")?.stringValue
        let bodyValue = remaining.removeValue(forKey: "body")
        let retry = remaining.removeValue(forKey: "retry")?.intValue ?? 0
        let type = remaining.removeValue(forKey: "type")?.stringValue
        let webView = remaining.removeValue(forKey: "webView")
        let webJavaScript = remaining.removeValue(forKey: "webJs")?.stringValue
        let javaScript = remaining.removeValue(forKey: "js")?.stringValue
        let proxy = remaining.removeValue(forKey: "proxy")?.stringValue
        let headerValue = remaining.removeValue(forKey: "headers")
        let optionHeaders: HTTPHeaders
        do {
            optionHeaders = try headers(from: headerValue, field: "URL option headers")
        } catch {
            if policy == .strict { throw error }
            optionHeaders = HTTPHeaders()
        }
        return RequestOptions(
            method: method,
            charset: charset,
            headers: optionHeaders,
            body: try bodyValue.map(jsonString),
            retry: retry,
            type: type,
            webView: webView,
            webJavaScript: webJavaScript,
            javaScript: javaScript,
            proxy: proxy,
            extraFields: remaining
        )
    }

    private func parseMethod(
        _ value: String?,
        policy: RuleParseContext.ErrorPolicy
    ) throws -> HTTPMethod {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .get }
        if value.caseInsensitiveCompare("POST") == .orderedSame { return .post }
        if value.caseInsensitiveCompare("GET") == .orderedSame { return .get }
        if policy == .strict { throw HTTPError.unsupportedMethod(value) }
        return .get
    }

    private func parseHeaders(_ text: String?, field: String) throws -> HTTPHeaders {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return HTTPHeaders()
        }
        do {
            let json = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
            return try headers(from: json, field: field)
        } catch let error as HTTPError {
            throw error
        } catch {
            throw HTTPError.invalidHeaders(field)
        }
    }

    private func headers(from value: JSONValue?, field: String) throws -> HTTPHeaders {
        guard let value else { return HTTPHeaders() }
        let object: [String: JSONValue]
        switch value {
        case let .object(values): object = values
        case let .string(text):
            guard let data = text.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(JSONValue.self, from: data),
                  case let .object(values) = decoded else { throw HTTPError.invalidHeaders(field) }
            object = values
        default: throw HTTPError.invalidHeaders(field)
        }
        return HTTPHeaders(object.keys.sorted().map {
            HTTPHeader(name: $0, value: object[$0]!.stringValue)
        })
    }

    private func resolveURL(_ value: String, baseURL: String?) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = URL(string: trimmed), direct.scheme != nil { return direct }
        guard let baseURL, let base = URL(string: splitOptions(baseURL).url) else { return nil }
        return URL(string: trimmed, relativeTo: base)?.absoluteURL
    }

    private func makeBody(
        _ body: String?,
        method: HTTPMethod,
        charset: String?,
        headers: inout HTTPHeaders
    ) throws -> (data: Data?, kind: HTTPBodyKind) {
        guard method == .post else { return (nil, .none) }
        let body = body ?? ""
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let isJSON = trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
        let isXML = trimmed.hasPrefix("<")
        if headers["Content-Type"] == nil, !isJSON, !isXML {
            headers["Content-Type"] = "application/x-www-form-urlencoded"
            return (Data(try formEncoded(body, charset: charset).utf8), .form)
        }
        if headers["Content-Type"] == nil {
            headers["Content-Type"] = "application/json; charset=UTF-8"
        }
        return (Data(body.utf8), .raw)
    }

    private func formEncoded(_ body: String, charset: String?) throws -> String {
        if let charset,
           !["utf-8", "utf8"].contains(charset.lowercased()) {
            throw HTTPError.unsupportedCharset(charset)
        }
        return body.split(separator: "&", omittingEmptySubsequences: true).map { field in
            let pieces = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = percentEncode(String(pieces[0]))
            let value = pieces.count == 2 ? percentEncode(String(pieces[1])) : ""
            return "\(name)=\(value)"
        }.joined(separator: "&")
    }

    private func resolveGETURL(
        _ value: String,
        baseURL: String?,
        charset: String?
    ) throws -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let fragmentStart = trimmed.firstIndex(of: "#")
        guard let queryStart = trimmed.firstIndex(of: "?"),
              fragmentStart.map({ queryStart < $0 }) ?? true else {
            return resolveURL(trimmed, baseURL: baseURL)
        }
        let queryEnd = fragmentStart ?? trimmed.endIndex
        let rawQuery = String(trimmed[trimmed.index(after: queryStart)..<queryEnd])
        guard !rawQuery.isEmpty else {
            return resolveURL(trimmed, baseURL: baseURL)
        }
        if let charset,
           !["utf-8", "utf8"].contains(charset.lowercased()) {
            throw HTTPError.unsupportedCharset(charset)
        }
        let encodedQuery = rawQuery.split(separator: "&", omittingEmptySubsequences: true).map { field in
            let pieces = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = encodeQueryComponent(String(pieces[0]))
            let value = pieces.count == 2 ? encodeQueryComponent(String(pieces[1])) : ""
            return "\(name)=\(value)"
        }.joined(separator: "&")
        let prefix = trimmed[..<queryStart]
        let fragment = fragmentStart.map { String(trimmed[$0...]) } ?? ""
        return resolveURL("\(prefix)?\(encodedQuery)\(fragment)", baseURL: baseURL)
    }

    private func encodeQueryComponent(_ value: String) -> String {
        var result = ""
        var index = value.startIndex
        while index < value.endIndex {
            let character = value[index]
            if character == "%" {
                let first = value.index(after: index)
                if first < value.endIndex {
                    let second = value.index(after: first)
                    if second < value.endIndex,
                       value[first].isHexDigit,
                       value[second].isHexDigit {
                        let escape = String(value[first...second])
                        result += escape.caseInsensitiveCompare("20") == .orderedSame
                            ? "+"
                            : "%\(escape)"
                        index = value.index(after: second)
                        continue
                    }
                }
            }
            if character == " " {
                result += "+"
            } else if isASCIIQueryUnreserved(character) {
                result.append(character)
            } else {
                for byte in String(character).utf8 {
                    result += String(format: "%%%02X", byte)
                }
            }
            index = value.index(after: index)
        }
        return result
    }

    private func isASCIIQueryUnreserved(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let value = character.unicodeScalars.first?.value,
              value < 128 else { return false }
        return (48...57).contains(value) ||
            (65...90).contains(value) ||
            (97...122).contains(value) ||
            [45, 46, 95, 126].contains(value)
    }

    private func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%20", with: "+") ?? value
    }

    private func mergeCookies(_ cookies: [HTTPCookie], into headers: inout HTTPHeaders) {
        var values: [String: String] = [:]
        for cookie in cookies { values[cookie.name] = cookie.value }
        if let custom = headers["Cookie"] {
            for pair in custom.split(separator: ";") {
                let pieces = pair.split(separator: "=", maxSplits: 1)
                if pieces.count == 2 {
                    values[pieces[0].trimmingCharacters(in: .whitespaces)] =
                        pieces[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        if !values.isEmpty {
            headers["Cookie"] = values.keys.sorted().map { "\($0)=\(values[$0]!)" }.joined(separator: "; ")
        }
    }

    private func jsonString(_ value: JSONValue) throws -> String {
        if case let .string(text) = value { return text }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

private extension JSONValue {
    var stringValue: String {
        switch self {
        case .null: return "null"
        case let .bool(value): return value ? "true" : "false"
        case let .integer(value): return String(value)
        case let .number(value): return String(value)
        case let .string(value): return value
        case .array, .object:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return (try? String(decoding: encoder.encode(self), as: UTF8.self)) ?? ""
        }
    }

    var intValue: Int? {
        switch self {
        case let .integer(value): return Int(exactly: value)
        case let .number(value): return Int(exactly: value)
        case let .string(value): return Int(value)
        default: return nil
        }
    }
}
