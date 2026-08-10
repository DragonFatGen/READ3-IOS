import Foundation

public struct BookSourceSearchRuntime: Sendable {
    private let httpClient: any HTTPClient
    private let requestBuilder: RequestBuilder
    private let selectorExecutor: any RuleNodeSelectorExecutor
    private let javaScriptExecutor: (any RuleJavaScriptExecutor)?
    private let textDecoder: any TextDecoder
    private let parser = RuleParser()
    private let urlResolver = URLResolver()

    public init(
        httpClient: any HTTPClient,
        requestBuilder: RequestBuilder = RequestBuilder(),
        selectorExecutor: any RuleNodeSelectorExecutor = LegadoRuleSelectorExecutor(),
        javaScriptExecutor: (any RuleJavaScriptExecutor)? = nil,
        textDecoder: any TextDecoder = FoundationTextDecoder()
    ) {
        self.httpClient = httpClient
        self.requestBuilder = requestBuilder
        self.selectorExecutor = selectorExecutor
        self.javaScriptExecutor = javaScriptExecutor
        self.textDecoder = textDecoder
    }

    public func search(
        source: BookSource,
        keyword: String,
        page: Int = 1
    ) async throws -> [BookSearchResult] {
        guard let searchURL = nonblank(source.searchUrl), let rules = source.ruleSearch,
              let rawBookList = nonblank(rules.bookList) else {
            throw BookSearchError.searchNotSupported
        }
        if requiresNetworkHost(searchURL) { throw BookSearchError.unsupportedJavaScriptNetworkHost }

        let request: HTTPRequest
        do {
            request = try await requestBuilder.build(
                searchURL,
                source: source,
                context: RequestBuildContext(
                    keyword: keyword,
                    page: page,
                    sourceURL: source.bookSourceUrl,
                    baseURL: source.bookSourceUrl,
                    sourceIdentifier: source.bookSourceUrl
                )
            )
        } catch {
            throw BookSearchError.requestBuildFailed(error.localizedDescription)
        }

        let response: HTTPResponse
        do { response = try await httpClient.send(request) }
        catch { throw BookSearchError.networkFailed(error.localizedDescription) }

        let body: String
        do { body = try response.text(decoder: textDecoder) }
        catch { throw BookSearchError.responseDecodeFailed(error.localizedDescription) }

        let baseURL = response.finalURL.absoluteString
        var listRule = rawBookList
        let reverse = listRule.hasPrefix("-")
        if reverse || listRule.hasPrefix("+") { listRule.removeFirst() }
        if requiresNetworkHost(listRule) { throw BookSearchError.unsupportedJavaScriptNetworkHost }

        let isJSON = Self.looksLikeJSON(body)
        let parseContext = RuleParseContext(contentIsJSON: isJSON)
        let listExpression: RuleExpression
        do { listExpression = try parser.parse(listRule, context: parseContext) }
        catch { throw BookSearchError.bookListRuleFailed(error.localizedDescription) }

        var listContext = makeContext(source: source, baseURL: baseURL)
        let collection: RuleNodeCollection
        do {
            collection = try RuleNodeExecutor(selectorExecutor: selectorExecutor).execute(
                listExpression,
                input: RuleExecutionInput(.string(body)),
                context: &listContext
            )
        } catch let error as RuleExecutionError {
            if case .unsupportedExecutionNode = error {
                throw BookSearchError.unsupportedStructuredRule(listRule)
            }
            throw BookSearchError.bookListRuleFailed(error.localizedDescription)
        } catch {
            throw BookSearchError.bookListRuleFailed(error.localizedDescription)
        }

        let nodes = reverse ? Array(collection.nodes.reversed()) : collection.nodes
        var results: [BookSearchResult] = []
        for node in nodes {
            if let result = try parseItem(node, rules: rules, source: source, baseURL: baseURL) {
                results.append(result)
            }
        }
        return results
    }

    private func parseItem(
        _ node: RuleNode,
        rules: SearchRule,
        source: BookSource,
        baseURL: String
    ) throws -> BookSearchResult? {
        var context = makeContext(source: source, baseURL: baseURL)
        let input = RuleExecutionInput(node: node)

        let name = formatName(try requiredField("name", rule: rules.name, input: input, context: &context))
        guard !name.isEmpty else { return nil }
        let author = formatAuthor(try requiredField("author", rule: rules.author, input: input, context: &context))

        let kind = try optionalField("kind", rule: rules.kind, input: input, context: &context, join: ",")
        let wordCount = formatWordCount(try optionalField("wordCount", rule: rules.wordCount, input: input, context: &context))
        let lastChapter = try optionalField("lastChapter", rule: rules.lastChapter, input: input, context: &context)
        let intro = formatIntro(try optionalField("intro", rule: rules.intro, input: input, context: &context))
        let coverRaw = try optionalField("coverUrl", rule: rules.coverUrl, input: input, context: &context)
        let coverURL = nonblank(coverRaw).map { urlResolver.resolve($0, against: baseURL) }
        let rawBookURL = try requiredField("bookUrl", rule: rules.bookUrl, input: input, context: &context)
        let bookURL = urlResolver.resolve(rawBookURL, against: baseURL)

        return BookSearchResult(
            name: name,
            author: author,
            bookURL: bookURL,
            coverURL: coverURL,
            intro: nonblank(intro),
            kind: nonblank(kind),
            wordCount: nonblank(wordCount),
            lastChapter: nonblank(lastChapter),
            sourceURL: source.bookSourceUrl,
            sourceName: source.bookSourceName,
            sourceType: source.bookSourceType,
            sourceOrder: source.customOrder
        )
    }

    private func requiredField(
        _ field: String,
        rule: String?,
        input: RuleExecutionInput,
        context: inout RuleExecutionContext
    ) throws -> String {
        guard let rule = nonblank(rule) else { return "" }
        if requiresNetworkHost(rule) { throw BookSearchError.unsupportedJavaScriptNetworkHost }
        do { return try executeField(rule, input: input, context: &context).stringValue }
        catch let error as BookSearchError { throw error }
        catch { throw BookSearchError.fieldRuleFailed(field: field, message: error.localizedDescription) }
    }

    private func optionalField(
        _ field: String,
        rule: String?,
        input: RuleExecutionInput,
        context: inout RuleExecutionContext,
        join: String = "\n"
    ) throws -> String? {
        guard let rule = nonblank(rule) else { return nil }
        if requiresNetworkHost(rule) { throw BookSearchError.unsupportedJavaScriptNetworkHost }
        do { return try executeField(rule, input: input, context: &context).stringValues.joined(separator: join) }
        catch { return nil }
    }

    private func executeField(
        _ rule: String,
        input: RuleExecutionInput,
        context: inout RuleExecutionContext
    ) throws -> RuleValue {
        context.currentResult = .none
        context.captureGroups = []
        let expression = try parser.parse(
            rule,
            context: RuleParseContext(contentIsJSON: input.node?.kind == .json)
        )
        return try RuleExecutor(
            selectorExecutor: selectorExecutor,
            javaScriptExecutor: javaScriptExecutor
        ).execute(expression, input: input, context: &context).value
    }

    private func makeContext(source: BookSource, baseURL: String) -> RuleExecutionContext {
        RuleExecutionContext(
            baseUrl: baseURL,
            javaScriptSource: JavaScriptSourceSnapshot(
                identifier: source.bookSourceUrl,
                url: source.bookSourceUrl,
                header: source.header
            )
        )
    }

    private func requiresNetworkHost(_ rule: String) -> Bool {
        let value = rule.lowercased()
        return ["java.ajax", "java.get", "java.post", "java.head"].contains { value.contains($0) }
    }

    private func nonblank(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private static func looksLikeJSON(_ value: String) -> Bool {
        guard let first = value.first(where: { !$0.isWhitespace }) else { return false }
        return first == "{" || first == "["
    }

    private func formatName(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"\s+作\s*者.*|\s+\S+\s+著"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatAuthor(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"^\s*作\s*者[:：\s]+|\s+著"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatWordCount(_ value: String?) -> String? {
        guard let value = nonblank(value) else { return nil }
        guard let count = Int(value), count > 0 else { return value }
        if count > 10_000 {
            let number = Double(count) / 10_000
            return String(
                format: number.rounded() == number ? "%.0f万字" : "%.1f万字",
                locale: Locale(identifier: "en_US_POSIX"),
                number
            )
        }
        return "\(count)字"
    }

    private func formatIntro(_ value: String?) -> String? {
        guard let value else { return nil }
        return value
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
