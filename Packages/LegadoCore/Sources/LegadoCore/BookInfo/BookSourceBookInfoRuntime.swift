import Foundation

public struct BookSourceBookInfoRuntime: Sendable {
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

    public func fetchBookInfo(
        source: BookSource,
        book: BookSearchResult
    ) async throws -> BookInfoResult {
        guard let rules = source.ruleBookInfo else { throw BookInfoError.bookInfoNotSupported }
        guard !book.bookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BookInfoError.emptyBookURL
        }
        if requiresNetworkHost(book.bookURL) { throw BookInfoError.unsupportedJavaScriptNetworkHost }

        let request: HTTPRequest
        do {
            request = try await requestBuilder.build(
                book.bookURL,
                source: source,
                context: RequestBuildContext(
                    sourceURL: source.bookSourceUrl,
                    baseURL: source.bookSourceUrl,
                    sourceIdentifier: source.bookSourceUrl
                )
            )
        } catch {
            throw BookInfoError.requestBuildFailed(error.localizedDescription)
        }

        let response: HTTPResponse
        do { response = try await httpClient.send(request) }
        catch { throw BookInfoError.networkFailed(error.localizedDescription) }

        let body: String
        do { body = try response.text(decoder: textDecoder) }
        catch { throw BookInfoError.responseDecodeFailed(error.localizedDescription) }

        return try parse(
            source: source,
            book: book,
            rules: rules,
            body: body,
            redirectURL: response.finalURL.absoluteString
        )
    }

    private func parse(
        source: BookSource,
        book: BookSearchResult,
        rules: BookInfoRule,
        body: String,
        redirectURL: String
    ) throws -> BookInfoResult {
        var context = RuleExecutionContext(
            baseUrl: book.bookURL,
            javaScriptSource: JavaScriptSourceSnapshot(
                identifier: source.bookSourceUrl,
                url: source.bookSourceUrl,
                header: source.header
            )
        )
        var input = RuleExecutionInput(.string(body))
        if let initialRule = nonblank(rules.`init`) {
            if requiresNetworkHost(initialRule) { throw BookInfoError.unsupportedJavaScriptNetworkHost }
            do {
                let expression = try parser.parse(
                    initialRule,
                    context: RuleParseContext(contentIsJSON: Self.looksLikeJSON(body))
                )
                guard let node = try RuleNodeExecutor(selectorExecutor: selectorExecutor)
                    .executeContext(expression, input: input, context: &context) else {
                    throw BookInfoError.initRuleFailed("The init rule returned no node.")
                }
                input = RuleExecutionInput(node: node)
            } catch let error as BookInfoError {
                throw error
            } catch let error as RuleExecutionError {
                if case .unsupportedExecutionNode = error {
                    throw BookInfoError.unsupportedStructuredRule(initialRule)
                }
                throw BookInfoError.initRuleFailed(error.localizedDescription)
            } catch {
                throw BookInfoError.initRuleFailed(error.localizedDescription)
            }
        }

        var name = book.name
        let parsedName = formatName(try requiredField("name", rule: rules.name, input: input, context: &context))
        if !parsedName.isEmpty, shouldRename(rules) || name.isEmpty { name = parsedName }

        var author = book.author
        let parsedAuthor = formatAuthor(try requiredField("author", rule: rules.author, input: input, context: &context))
        if !parsedAuthor.isEmpty, shouldRename(rules) || author.isEmpty { author = parsedAuthor }

        let kind = try optionalField(rules.kind, input: input, context: &context, join: ",") ?? book.kind
        let wordCount = formatWordCount(
            try optionalField(rules.wordCount, input: input, context: &context)
        ) ?? book.wordCount
        let lastChapter = try optionalField(rules.lastChapter, input: input, context: &context) ?? book.lastChapter
        let intro = formatIntro(try optionalField(rules.intro, input: input, context: &context)) ?? book.intro

        var coverURL = book.coverURL
        if let cover = nonblank(try optionalField(rules.coverUrl, input: input, context: &context)) {
            coverURL = urlResolver.resolve(cover, against: redirectURL)
        }

        let tocRaw = try requiredField("tocUrl", rule: rules.tocUrl, input: input, context: &context)
        let tocURL = nonblank(tocRaw).map { urlResolver.resolve($0, against: redirectURL) } ?? book.bookURL

        return BookInfoResult(
            name: name,
            author: author,
            bookURL: book.bookURL,
            coverURL: coverURL,
            intro: intro,
            kind: nonblank(kind),
            wordCount: nonblank(wordCount),
            lastChapter: nonblank(lastChapter),
            tocURL: tocURL,
            sourceURL: book.sourceURL,
            sourceName: book.sourceName,
            sourceType: book.sourceType,
            sourceOrder: book.sourceOrder
        )
    }

    private func requiredField(
        _ field: String,
        rule: String?,
        input: RuleExecutionInput,
        context: inout RuleExecutionContext
    ) throws -> String {
        guard let rule = nonblank(rule) else { return "" }
        if requiresNetworkHost(rule) { throw BookInfoError.unsupportedJavaScriptNetworkHost }
        do { return try executeField(rule, input: input, context: &context).stringValue }
        catch let error as BookInfoError { throw error }
        catch { throw BookInfoError.fieldRuleFailed(field: field, message: error.localizedDescription) }
    }

    private func optionalField(
        _ rule: String?,
        input: RuleExecutionInput,
        context: inout RuleExecutionContext,
        join: String = "\n"
    ) throws -> String? {
        guard let rule = nonblank(rule) else { return nil }
        if requiresNetworkHost(rule) { throw BookInfoError.unsupportedJavaScriptNetworkHost }
        do {
            let value = try executeField(rule, input: input, context: &context)
                .stringValues.joined(separator: join)
            return nonblank(value)
        } catch let error as BookInfoError {
            throw error
        } catch {
            // Android logs optional field failures and retains the previous Book value.
            return nil
        }
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

    private func shouldRename(_ rules: BookInfoRule) -> Bool { nonblank(rules.canReName) != nil }

    private func requiresNetworkHost(_ value: String) -> Bool {
        let value = value.lowercased()
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
        value.replacingOccurrences(of: #"\s+作\s*者.*|\s+\S+\s+著"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatAuthor(_ value: String) -> String {
        value.replacingOccurrences(of: #"^\s*作\s*者[:：\s]+|\s+著"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatWordCount(_ value: String?) -> String? {
        guard let value = nonblank(value), let count = Int(value), count > 0 else { return nonblank(value) }
        if count > 10_000 {
            let number = Double(count) / 10_000
            return String(format: number.rounded() == number ? "%.0f万字" : "%.1f万字",
                          locale: Locale(identifier: "en_US_POSIX"), number)
        }
        return "\(count)字"
    }

    private func formatIntro(_ value: String?) -> String? {
        guard let value else { return nil }
        return nonblank(value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " "))
    }
}
