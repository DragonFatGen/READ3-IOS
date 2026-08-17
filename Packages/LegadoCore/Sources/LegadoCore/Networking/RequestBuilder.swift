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

public struct RequestBuildResult: Sendable, Equatable {
    public let request: HTTPRequest
    public let temporaryVariables: [String: String]
    public let variableWrites: [String: String]

    public init(
        request: HTTPRequest,
        temporaryVariables: [String: String],
        variableWrites: [String: String]
    ) {
        self.request = request
        self.temporaryVariables = temporaryVariables
        self.variableWrites = variableWrites
    }
}

public struct RequestBuilder: Sendable {
    private let cookieStore: (any HTTPCookieStore)?
    private let textEncoder: any TextEncoder
    private let javaScriptExecutor: (any RuleJavaScriptExecutor)?

    public init(
        cookieStore: (any HTTPCookieStore)? = nil,
        textEncoder: any TextEncoder = FoundationTextEncoder(),
        javaScriptExecutor: (any RuleJavaScriptExecutor)? = nil
    ) {
        self.cookieStore = cookieStore
        self.textEncoder = textEncoder
        self.javaScriptExecutor = javaScriptExecutor
    }

    public func build(
        _ legadoURL: String,
        source: BookSource,
        context: RequestBuildContext = RequestBuildContext()
    ) async throws -> HTTPRequest {
        try await buildResult(legadoURL, source: source, context: context).request
    }

    public func buildResult(
        _ legadoURL: String,
        source: BookSource,
        context: RequestBuildContext = RequestBuildContext()
    ) async throws -> RequestBuildResult {
        var resolvedContext = context
        if resolvedContext.sourceURL == nil { resolvedContext.sourceURL = source.bookSourceUrl }
        if resolvedContext.baseURL == nil { resolvedContext.baseURL = source.bookSourceUrl }
        if resolvedContext.sourceIdentifier == nil { resolvedContext.sourceIdentifier = source.bookSourceUrl }
        return try await buildResult(legadoURL, sourceHeader: source.header, context: resolvedContext)
    }

    public func build(
        _ legadoURL: String,
        sourceHeader: String? = nil,
        context: RequestBuildContext = RequestBuildContext()
    ) async throws -> HTTPRequest {
        try await buildResult(legadoURL, sourceHeader: sourceHeader, context: context).request
    }

    public func buildResult(
        _ legadoURL: String,
        sourceHeader: String? = nil,
        context: RequestBuildContext = RequestBuildContext()
    ) async throws -> RequestBuildResult {
        let renderResult = try render(legadoURL, sourceHeader: sourceHeader, context: context)
        let parts = splitOptions(renderResult.value)
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

        let requestURL = try applyOptionJavaScript(
            options.javaScript,
            to: parts.url,
            sourceHeader: sourceHeader,
            context: context
        )
        let resolvedURL = if method == .get {
            try resolveGETURL(requestURL, baseURL: context.baseURL, charset: options.charset)
        } else {
            resolveURL(requestURL, baseURL: context.baseURL)
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
        let request = HTTPRequest(
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
        return RequestBuildResult(
            request: request,
            temporaryVariables: renderResult.temporaryVariables,
            variableWrites: renderResult.variableWrites
        )
    }

    private func render(
        _ value: String,
        sourceHeader: String?,
        context: RequestBuildContext
    ) throws -> (
        value: String,
        temporaryVariables: [String: String],
        variableWrites: [String: String]
    ) {
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
        normalized = try renderJavaScriptTemplates(
            normalized,
            sourceHeader: sourceHeader,
            context: context,
            variables: variables
        )
        let hasPut = normalized.range(of: "@put:{", options: .caseInsensitive) != nil
        let hasTemplateRead = normalized.contains("{{") ||
            normalized.range(of: "@get:{", options: .caseInsensitive) != nil
        let hasJavaScript = normalized.range(of: "@js:", options: .caseInsensitive) != nil ||
            normalized.range(of: "<js>", options: .caseInsensitive) != nil
        if hasPut, !hasTemplateRead, !hasJavaScript {
            // A request URL is literal text, while the general rule parser treats a
            // bare expression as a selector. An empty compatible template keeps the
            // URL literal and still lets the surrounding @put persist its variables.
            normalized += "{{}}"
        }
        guard normalized.contains("{{") ||
                normalized.range(of: "@get:{", options: .caseInsensitive) != nil ||
                normalized.range(of: "@put:{", options: .caseInsensitive) != nil ||
                normalized.range(of: "@js:", options: .caseInsensitive) != nil ||
                normalized.range(of: "<js>", options: .caseInsensitive) != nil else {
            return (replacePageAlternatives(normalized, page: context.page), variables, [:])
        }
        var executionContext = RuleExecutionContext(
            baseUrl: context.baseURL ?? "",
            sourceVariables: context.sourceVariables,
            temporaryVariables: variables,
            errorPolicy: context.errorPolicy
        )
        let expression = try RuleParser().parse(normalized, context: RuleParseContext(errorPolicy: context.errorPolicy))
        let rendered = try RuleExecutor(javaScriptExecutor: javaScriptExecutor).execute(
            expression,
            input: RuleExecutionInput(.string(value)),
            context: &executionContext
        ).value.stringValue
        let snapshot = executionContext.temporaryVariables.snapshot
        let writes = snapshot.filter { variables[$0.key] != $0.value }
        return (replacePageAlternatives(rendered, page: context.page), snapshot, writes)
    }

    private func renderJavaScriptTemplates(
        _ value: String,
        sourceHeader: String?,
        context: RequestBuildContext,
        variables: [String: String]
    ) throws -> String {
        var result = value
        while let open = result.range(of: "{{"),
              let close = result.range(of: "}}", range: open.upperBound..<result.endIndex) {
            guard let javaScriptExecutor else {
                throw JavaScriptExecutionError.evaluationFailed("No JavaScript executor is configured.")
            }
            let script = String(result[open.upperBound..<close.lowerBound])
            let output = try javaScriptExecutor.execute(
                script: script,
                context: JavaScriptExecutionContext(
                    result: .none,
                    baseUrl: context.baseURL ?? "",
                    source: javaScriptSource(sourceHeader: sourceHeader, context: context),
                    sourceVariables: context.sourceVariables,
                    temporaryVariables: variables
                )
            ).templateString
            result.replaceSubrange(open.lowerBound..<close.upperBound, with: output)
        }
        return result
    }

    private func applyOptionJavaScript(
        _ script: String?,
        to value: String,
        sourceHeader: String?,
        context: RequestBuildContext
    ) throws -> String {
        guard let script, !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return value
        }
        guard let javaScriptExecutor else { return value }
        let absoluteValue = resolveURL(value, baseURL: context.baseURL)?.absoluteString ?? value
        var variables = context.sourceVariables
        if let keyword = context.keyword {
            variables["key"] = keyword
            variables["keyword"] = keyword
        }
        if let page = context.page { variables["page"] = String(page) }
        if let pageSize = context.pageSize { variables["pageSize"] = String(pageSize) }
        return try javaScriptExecutor.execute(
            script: script,
            context: JavaScriptExecutionContext(
                result: .string(absoluteValue),
                baseUrl: context.baseURL ?? "",
                source: javaScriptSource(sourceHeader: sourceHeader, context: context),
                sourceVariables: context.sourceVariables,
                temporaryVariables: variables
            )
        ).ruleValue.stringValue
    }

    private func javaScriptSource(
        sourceHeader: String?,
        context: RequestBuildContext
    ) -> JavaScriptSourceSnapshot? {
        guard let sourceURL = context.sourceURL else { return nil }
        return JavaScriptSourceSnapshot(
            identifier: context.sourceIdentifier ?? sourceURL,
            url: sourceURL,
            header: sourceHeader
        )
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
        let bodyCharset = contentTypeCharset(headers["Content-Type"]) ?? "UTF-8"
        return (try textEncoder.encode(body, charset: bodyCharset), .raw)
    }

    private func formEncoded(_ body: String, charset: String?) throws -> String {
        return try body.split(separator: "&", omittingEmptySubsequences: true).map { field in
            let pieces = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = try percentEncode(String(pieces[0]), charset: "UTF-8")
            let value = pieces.count == 2
                ? try percentEncode(String(pieces[1]), charset: charset)
                : ""
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
        let encodedQuery = try rawQuery.split(separator: "&", omittingEmptySubsequences: true).map { field in
            let pieces = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = try encodeQueryComponent(String(pieces[0]), charset: nil)
            let value = pieces.count == 2
                ? try encodeQueryComponent(String(pieces[1]), charset: charset)
                : ""
            return "\(name)=\(value)"
        }.joined(separator: "&")
        let prefix = trimmed[..<queryStart]
        let fragment = fragmentStart.map { String(trimmed[$0...]) } ?? ""
        return resolveURL("\(prefix)?\(encodedQuery)\(fragment)", baseURL: baseURL)
    }

    private func encodeQueryComponent(_ value: String, charset: String?) throws -> String {
        if charset != nil {
            return try percentEncode(value, charset: charset)
        }
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

    private func percentEncode(_ value: String, charset: String?) throws -> String {
        let bytes = try textEncoder.encode(value, charset: charset ?? "UTF-8")
        return bytes.map { byte in
            if isFormUnreserved(byte) { return String(UnicodeScalar(byte)) }
            if byte == 0x20 { return "+" }
            return String(format: "%%%02X", byte)
        }.joined()
    }

    private func isFormUnreserved(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) ||
            (65...90).contains(byte) ||
            (97...122).contains(byte) ||
            [45, 46, 95, 126].contains(byte)
    }

    private func contentTypeCharset(_ contentType: String?) -> String? {
        guard let contentType else { return nil }
        for part in contentType.split(separator: ";").dropFirst() {
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2,
                  pair[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare("charset") == .orderedSame else { continue }
            return pair[1]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
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
