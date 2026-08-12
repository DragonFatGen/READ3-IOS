import Foundation

public struct BookSourceContentRuntime: Sendable {
    private let httpClient: any HTTPClient
    private let requestBuilder: RequestBuilder
    private let selectorExecutor: any RuleNodeSelectorExecutor
    private let javaScriptExecutor: (any RuleJavaScriptExecutor)?
    private let textDecoder: any TextDecoder
    private let maximumPageCount: Int
    private let parser = RuleParser()
    private let urlResolver = URLResolver()
    private let formatter = AndroidContentFormatter()

    public init(
        httpClient: any HTTPClient,
        requestBuilder: RequestBuilder = RequestBuilder(),
        selectorExecutor: any RuleNodeSelectorExecutor = LegadoRuleSelectorExecutor(),
        javaScriptExecutor: (any RuleJavaScriptExecutor)? = nil,
        textDecoder: any TextDecoder = FoundationTextDecoder(),
        maximumPageCount: Int = 100
    ) {
        self.httpClient = httpClient
        self.requestBuilder = requestBuilder
        self.selectorExecutor = selectorExecutor
        self.javaScriptExecutor = javaScriptExecutor
        self.textDecoder = textDecoder
        self.maximumPageCount = max(1, maximumPageCount)
    }

    public func fetchContent(
        source: BookSource,
        book: BookInfoResult,
        chapter: BookChapterResult
    ) async throws -> ChapterContentResult {
        let rules = source.ruleContent ?? ContentRule()
        guard let contentRule = rules.content, !contentRule.isEmpty else {
            return ChapterContentResult(content: chapter.url, chapterURL: chapter.url)
        }
        if requiresNetworkHost(contentRule) ||
            rules.nextContentUrl.map(requiresNetworkHost) == true ||
            rules.replaceRegex.map(requiresNetworkHost) == true {
            throw ContentError.unsupportedJavaScriptNetworkHost
        }

        var chapterVariables: [String: String] = [:]
        let firstResponse = try await request(
            chapter.url,
            source: source,
            baseURL: book.tocURL
        )
        let firstPage = ContentPage(
            requestURL: chapter.url,
            redirectURL: firstResponse.finalURL.absoluteString,
            response: firstResponse
        )
        var parsed = try parse(
            firstPage,
            rules: rules,
            source: source,
            variables: &chapterVariables,
            readsNextPage: true
        )
        var content = parsed.content

        if parsed.nextURLs.count == 1 {
            var visited = Set([firstPage.redirectURL])
            var nextURL = parsed.nextURLs[0]
            var pageCount = 1
            while !nextURL.isEmpty, !visited.contains(nextURL) {
                guard pageCount < maximumPageCount else {
                    throw ContentError.paginationLimitExceeded(maximumPageCount)
                }
                visited.insert(nextURL)
                pageCount += 1
                let response = try await request(nextURL, source: source, baseURL: "")
                parsed = try parse(
                    ContentPage(
                        requestURL: nextURL,
                        redirectURL: response.finalURL.absoluteString,
                        response: response
                    ),
                    rules: rules,
                    source: source,
                    variables: &chapterVariables,
                    readsNextPage: true
                )
                content += "\n" + parsed.content
                nextURL = parsed.nextURLs.first ?? ""
            }
        } else if parsed.nextURLs.count > 1 {
            guard parsed.nextURLs.count + 1 <= maximumPageCount else {
                throw ContentError.paginationLimitExceeded(maximumPageCount)
            }
            let pages = try await requestPages(parsed.nextURLs, source: source)
            for page in pages {
                let pageContent = try parse(
                    page,
                    rules: rules,
                    source: source,
                    variables: &chapterVariables,
                    readsNextPage: false
                ).content
                content += "\n" + pageContent
            }
        }

        if let purificationRule = rules.replaceRegex, !purificationRule.isEmpty {
            content = try purify(
                content,
                rule: purificationRule,
                source: source,
                baseURL: chapter.url,
                variables: &chapterVariables
            )
        }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ContentError.emptyContent
        }
        return ChapterContentResult(content: content, chapterURL: chapter.url)
    }

    private func requestPages(
        _ urls: [String],
        source: BookSource
    ) async throws -> [ContentPage] {
        try await withThrowingTaskGroup(of: IndexedContentPage.self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    let response = try await request(url, source: source, baseURL: "")
                    return IndexedContentPage(
                        index: index,
                        page: ContentPage(
                            requestURL: url,
                            redirectURL: response.finalURL.absoluteString,
                            response: response
                        )
                    )
                }
            }
            var pages: [IndexedContentPage] = []
            for try await page in group { pages.append(page) }
            return pages.sorted { $0.index < $1.index }.map(\.page)
        }
    }

    private func request(
        _ url: String,
        source: BookSource,
        baseURL: String
    ) async throws -> HTTPResponse {
        let request: HTTPRequest
        do {
            request = try await requestBuilder.build(
                url,
                source: source,
                context: RequestBuildContext(
                    sourceURL: source.bookSourceUrl,
                    baseURL: baseURL,
                    sourceIdentifier: source.bookSourceUrl
                )
            )
        } catch {
            throw ContentError.requestBuildFailed(
                url: url,
                message: error.localizedDescription
            )
        }
        do { return try await httpClient.send(request) }
        catch {
            throw ContentError.networkFailed(url: url, message: error.localizedDescription)
        }
    }

    private func parse(
        _ page: ContentPage,
        rules: ContentRule,
        source: BookSource,
        variables: inout [String: String],
        readsNextPage: Bool
    ) throws -> ParsedContentPage {
        let body: String
        do { body = try page.response.text(decoder: textDecoder) }
        catch {
            throw ContentError.responseDecodeFailed(
                url: page.requestURL,
                message: error.localizedDescription
            )
        }
        let contentIsJSON = Self.looksLikeJSON(body)
        var context = makeContext(
            baseURL: page.requestURL,
            source: source,
            variables: variables
        )
        let responseInput = RuleExecutionInput(.string(body))
        let nodeExecutor = RuleNodeExecutor(
            selectorExecutor: selectorExecutor,
            javaScriptExecutor: javaScriptExecutor
        )
        let rootInput: RuleExecutionInput
        do {
            rootInput = try nodeExecutor.makeRootContext(
                input: responseInput,
                contentIsJSON: contentIsJSON,
                context: &context
            )
        } catch {
            throw ContentError.contentRuleFailed(error.localizedDescription)
        }

        let rawContent: String
        do {
            rawContent = try executeScalar(
                rules.content ?? "",
                rootInput: rootInput,
                responseInput: responseInput,
                contentIsJSON: contentIsJSON,
                context: &context
            ).stringValue
        } catch let error as RuleExecutionError {
            if case .unsupportedExecutionNode = error {
                throw ContentError.unsupportedStructuredRule(rules.content ?? "")
            }
            throw ContentError.contentRuleFailed(error.localizedDescription)
        } catch let error as ContentError {
            throw error
        } catch {
            throw ContentError.contentRuleFailed(error.localizedDescription)
        }

        let nextURLs: [String]
        if readsNextPage, let rule = rules.nextContentUrl, !rule.isEmpty {
            context.currentResult = .none
            context.captureGroups = []
            do {
                let value = try executeScalar(
                    rule,
                    rootInput: rootInput,
                    responseInput: responseInput,
                    contentIsJSON: contentIsJSON,
                    context: &context
                )
                nextURLs = resolveURLList(value, against: page.redirectURL)
            } catch let error as RuleExecutionError {
                if case .unsupportedExecutionNode = error {
                    throw ContentError.unsupportedStructuredRule(rule)
                }
                throw ContentError.nextPageRuleFailed(error.localizedDescription)
            } catch let error as ContentError {
                throw error
            } catch {
                throw ContentError.nextPageRuleFailed(error.localizedDescription)
            }
        } else {
            nextURLs = []
        }
        variables.merge(context.temporaryVariables.snapshot) { _, new in new }
        return ParsedContentPage(
            content: formatter.format(rawContent, redirectURL: page.redirectURL),
            nextURLs: nextURLs
        )
    }

    private func executeScalar(
        _ rule: String,
        rootInput: RuleExecutionInput,
        responseInput: RuleExecutionInput,
        contentIsJSON: Bool,
        context: inout RuleExecutionContext
    ) throws -> RuleValue {
        let expression = try parser.parse(
            rule,
            context: RuleParseContext(contentIsJSON: contentIsJSON)
        )
        let input = if case .javaScript = expression {
            responseInput
        } else {
            rootInput
        }
        return try RuleExecutor(
            selectorExecutor: selectorExecutor,
            javaScriptExecutor: javaScriptExecutor
        ).execute(expression, input: input, context: &context).value
    }

    private func purify(
        _ content: String,
        rule: String,
        source: BookSource,
        baseURL: String,
        variables: inout [String: String]
    ) throws -> String {
        var context = makeContext(baseURL: baseURL, source: source, variables: variables)
        do {
            let expression = try parser.parse(rule)
            let value = try RuleExecutor(
                selectorExecutor: selectorExecutor,
                javaScriptExecutor: javaScriptExecutor
            ).execute(
                expression,
                input: RuleExecutionInput(.string(content)),
                context: &context
            ).value.stringValue
            variables.merge(context.temporaryVariables.snapshot) { _, new in new }
            return value
        } catch {
            throw ContentError.purificationRuleFailed(error.localizedDescription)
        }
    }

    private func makeContext(
        baseURL: String,
        source: BookSource,
        variables: [String: String]
    ) -> RuleExecutionContext {
        RuleExecutionContext(
            baseUrl: baseURL,
            javaScriptSource: JavaScriptSourceSnapshot(
                identifier: source.bookSourceUrl,
                url: source.bookSourceUrl,
                header: source.header
            ),
            sourceVariables: variables
        )
    }

    private func resolveURLList(_ value: RuleValue, against baseURL: String) -> [String] {
        let candidates: [String]
        switch value {
        case .none:
            candidates = []
        case let .string(value):
            candidates = value.components(separatedBy: "\n")
        case let .strings(values):
            candidates = values
        }
        var seen: Set<String> = []
        return candidates.compactMap { candidate in
            guard !candidate.isEmpty else { return nil }
            let resolved = resolveLegadoURL(candidate, against: baseURL)
            guard !resolved.isEmpty, seen.insert(resolved).inserted else { return nil }
            return resolved
        }
    }

    private func resolveLegadoURL(_ value: String, against baseURL: String) -> String {
        let pattern = #"\s*,\s*(?=\{)"#
        let base = baseURL.range(of: pattern, options: .regularExpression).map {
            String(baseURL[..<$0.lowerBound])
        } ?? baseURL
        guard let boundary = value.range(of: pattern, options: .regularExpression) else {
            return urlResolver.resolve(value, against: base)
        }
        let url = String(value[..<boundary.lowerBound])
        let options = String(value[boundary.upperBound...])
        return "\(urlResolver.resolve(url, against: base)),\(options)"
    }

    private func requiresNetworkHost(_ rule: String) -> Bool {
        let value = rule.lowercased()
        return ["java.ajax", "java.get", "java.post", "java.head"].contains {
            value.contains($0)
        }
    }

    private static func looksLikeJSON(_ value: String) -> Bool {
        guard let first = value.first(where: { !$0.isWhitespace }) else { return false }
        return first == "{" || first == "["
    }
}

private struct ContentPage: Sendable {
    let requestURL: String
    let redirectURL: String
    let response: HTTPResponse
}

private struct IndexedContentPage: Sendable {
    let index: Int
    let page: ContentPage
}

private struct ParsedContentPage {
    let content: String
    let nextURLs: [String]
}
