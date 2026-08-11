import Foundation

public struct BookSourceTOCRuntime: Sendable {
    private let httpClient: any HTTPClient
    private let requestBuilder: RequestBuilder
    private let selectorExecutor: any RuleNodeSelectorExecutor
    private let javaScriptExecutor: (any RuleJavaScriptExecutor)?
    private let textDecoder: any TextDecoder
    private let maximumPageCount: Int
    private let parser = RuleParser()
    private let urlResolver = URLResolver()

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

    public func fetchTOC(
        source: BookSource,
        book: BookInfoResult
    ) async throws -> [BookChapterResult] {
        let rules = source.ruleToc ?? TocRule()
        if requiresNetworkHost(book.tocURL) {
            throw TOCError.unsupportedJavaScriptNetworkHost
        }

        var bookVariables: [String: String] = [:]
        var chapters: [ParsedChapter] = []
        let firstResponse = try await request(book.tocURL, source: source, baseURL: book.bookURL)
        let firstPage = Page(
            requestURL: book.tocURL,
            baseURL: book.tocURL,
            redirectURL: firstResponse.finalURL.absoluteString,
            response: firstResponse
        )
        let first = try parse(
            firstPage, rules: rules, source: source,
            bookVariables: &bookVariables, readsNextPage: true
        )
        chapters.append(contentsOf: first.chapters)

        if first.nextURLs.count == 1 {
            var visited = Set([firstPage.redirectURL])
            var nextURL = first.nextURLs[0]
            var pageCount = 1
            while !nextURL.isEmpty, !visited.contains(nextURL) {
                guard pageCount < maximumPageCount else {
                    throw TOCError.paginationLimitExceeded(maximumPageCount)
                }
                visited.insert(nextURL)
                pageCount += 1
                let response = try await request(nextURL, source: source, baseURL: "")
                // Android's sequential branch uses the requested next URL for both
                // AnalyzeRule bases, even when that request redirected.
                let page = Page(
                    requestURL: nextURL,
                    baseURL: nextURL,
                    redirectURL: nextURL,
                    response: response
                )
                let parsed = try parse(
                    page, rules: rules, source: source,
                    bookVariables: &bookVariables, readsNextPage: true
                )
                chapters.append(contentsOf: parsed.chapters)
                nextURL = parsed.nextURLs.first ?? ""
            }
        } else if first.nextURLs.count > 1 {
            guard first.nextURLs.count + 1 <= maximumPageCount else {
                throw TOCError.paginationLimitExceeded(maximumPageCount)
            }
            let pages = try await requestPages(first.nextURLs, source: source)
            for page in pages {
                let parsed = try parse(
                    page, rules: rules, source: source,
                    bookVariables: &bookVariables, readsNextPage: false
                )
                chapters.append(contentsOf: parsed.chapters)
            }
        }

        guard !chapters.isEmpty else { throw TOCError.emptyChapterList }
        return finalize(
            chapters,
            reversedByRule: normalizedListRule(rules.chapterList).reverse,
            bookURL: book.bookURL,
            sourceURL: source.bookSourceUrl
        )
    }

    private func requestPages(_ urls: [String], source: BookSource) async throws -> [Page] {
        try await withThrowingTaskGroup(of: IndexedPage.self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    let response = try await request(url, source: source, baseURL: "")
                    return IndexedPage(index: index, page: Page(
                        requestURL: url,
                        baseURL: url,
                        redirectURL: response.finalURL.absoluteString,
                        response: response
                    ))
                }
            }
            var pages: [IndexedPage] = []
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
            throw TOCError.requestBuildFailed(url: url, message: error.localizedDescription)
        }
        do { return try await httpClient.send(request) }
        catch { throw TOCError.networkFailed(url: url, message: error.localizedDescription) }
    }

    private func parse(
        _ page: Page,
        rules: TocRule,
        source: BookSource,
        bookVariables: inout [String: String],
        readsNextPage: Bool
    ) throws -> ParsedPage {
        let body: String
        do { body = try page.response.text(decoder: textDecoder) }
        catch {
            throw TOCError.responseDecodeFailed(
                url: page.requestURL,
                message: error.localizedDescription
            )
        }

        var pageContext = makeContext(
            baseURL: page.baseURL,
            source: source,
            variables: bookVariables
        )
        let responseInput = RuleExecutionInput(.string(body))
        let contentIsJSON = Self.looksLikeJSON(body)
        let nodeExecutor = RuleNodeExecutor(
            selectorExecutor: selectorExecutor,
            javaScriptExecutor: javaScriptExecutor
        )
        let rootInput: RuleExecutionInput
        do {
            rootInput = try nodeExecutor.makeRootContext(
                input: responseInput,
                contentIsJSON: contentIsJSON,
                context: &pageContext
            )
        } catch {
            throw TOCError.chapterListRuleFailed(error.localizedDescription)
        }

        let list = normalizedListRule(rules.chapterList)
        if requiresNetworkHost(list.rule) {
            throw TOCError.unsupportedJavaScriptNetworkHost
        }
        let items: RuleNodeCollection
        do {
            let expression = try parser.parse(
                list.rule,
                context: RuleParseContext(contentIsJSON: contentIsJSON)
            )
            items = try nodeExecutor.execute(expression, input: rootInput, context: &pageContext)
        } catch let error as RuleExecutionError {
            if case .unsupportedExecutionNode = error {
                throw TOCError.unsupportedStructuredRule(list.rule)
            }
            throw TOCError.chapterListRuleFailed(error.localizedDescription)
        } catch let error as TOCError {
            throw error
        } catch {
            throw TOCError.chapterListRuleFailed(error.localizedDescription)
        }

        let nextURLs: [String]
        if readsNextPage, let nextRule = nonblank(rules.nextTocUrl) {
            if requiresNetworkHost(nextRule) {
                throw TOCError.unsupportedJavaScriptNetworkHost
            }
            do {
                let expression = try parser.parse(
                    nextRule,
                    context: RuleParseContext(contentIsJSON: contentIsJSON)
                )
                let executionInput = if case .javaScript = expression {
                    responseInput
                } else {
                    rootInput
                }
                let value = try RuleExecutor(
                    selectorExecutor: selectorExecutor,
                    javaScriptExecutor: javaScriptExecutor
                ).execute(expression, input: executionInput, context: &pageContext).value
                nextURLs = resolveURLList(value, against: page.redirectURL)
                    .filter { $0 != page.redirectURL }
            } catch {
                throw TOCError.nextPageRuleFailed(error.localizedDescription)
            }
        } else {
            nextURLs = []
        }

        bookVariables.merge(pageContext.temporaryVariables.snapshot) { _, new in new }
        var parsedChapters: [ParsedChapter] = []
        for (itemIndex, item) in items.nodes.enumerated() {
            var itemContext = makeContext(
                baseURL: page.baseURL,
                source: source,
                variables: bookVariables
            )
            let itemInput = RuleExecutionInput(node: item)
            let name = try field(
                "chapterName", rule: rules.chapterName, itemIndex: itemIndex,
                input: itemInput, context: &itemContext
            )
            var rawURL = try field(
                "chapterUrl", rule: rules.chapterUrl, itemIndex: itemIndex,
                input: itemInput, context: &itemContext
            )
            let tag = try field(
                "updateTime", rule: rules.updateTime, itemIndex: itemIndex,
                input: itemInput, context: &itemContext
            )
            let isVolume = Self.isTrue(try field(
                "isVolume", rule: rules.isVolume, itemIndex: itemIndex,
                input: itemInput, context: &itemContext
            ))
            if rawURL.isEmpty {
                rawURL = isVolume ? name + String(itemIndex) : page.baseURL
            }
            guard !name.isEmpty else { continue }
            let isVIP = Self.isTrue(try field(
                "isVip", rule: rules.isVip, itemIndex: itemIndex,
                input: itemInput, context: &itemContext
            ))
            let isPay = Self.isTrue(try field(
                "isPay", rule: rules.isPay, itemIndex: itemIndex,
                input: itemInput, context: &itemContext
            ))
            let resolvedURL = isVolume && rawURL.hasPrefix(name)
                ? page.redirectURL
                : resolveLegadoURL(rawURL, against: page.redirectURL)
            parsedChapters.append(ParsedChapter(
                name: name,
                rawURL: rawURL,
                resolvedURL: resolvedURL,
                isVolume: isVolume,
                isVIP: isVIP,
                isPay: isPay,
                tag: tag
            ))
        }
        return ParsedPage(chapters: parsedChapters, nextURLs: nextURLs)
    }

    private func field(
        _ field: String,
        rule: String?,
        itemIndex: Int,
        input: RuleExecutionInput,
        context: inout RuleExecutionContext
    ) throws -> String {
        guard let rule = nonblank(rule) else { return "" }
        if requiresNetworkHost(rule) { throw TOCError.unsupportedJavaScriptNetworkHost }
        context.currentResult = .none
        context.captureGroups = []
        do {
            let contentIsJSON = input.node?.kind == .json
            let expression = try parser.parse(
                rule,
                context: RuleParseContext(contentIsJSON: contentIsJSON)
            )
            return try RuleExecutor(
                selectorExecutor: selectorExecutor,
                javaScriptExecutor: javaScriptExecutor
            ).execute(expression, input: input, context: &context).value.stringValue
        } catch let error as TOCError {
            throw error
        } catch {
            throw TOCError.chapterFieldRuleFailed(
                index: itemIndex,
                field: field,
                message: error.localizedDescription
            )
        }
    }

    private func finalize(
        _ chapters: [ParsedChapter],
        reversedByRule: Bool,
        bookURL: String,
        sourceURL: String
    ) -> [BookChapterResult] {
        var ordered = chapters
        if !reversedByRule { ordered.reverse() }
        var seen: Set<String> = []
        ordered = ordered.filter { seen.insert($0.rawURL).inserted }
        ordered.reverse()
        return ordered.enumerated().map { index, chapter in
            BookChapterResult(
                name: chapter.name,
                url: chapter.resolvedURL,
                isVolume: chapter.isVolume,
                index: index,
                isVIP: chapter.isVIP,
                isPay: chapter.isPay,
                tag: chapter.tag,
                bookURL: bookURL,
                sourceURL: sourceURL
            )
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

    private func normalizedListRule(_ value: String?) -> (rule: String, reverse: Bool) {
        var rule = value ?? ""
        let reverse = rule.hasPrefix("-")
        if reverse { rule.removeFirst() }
        if rule.hasPrefix("+") { rule.removeFirst() }
        return (rule, reverse)
    }

    private func resolveURLList(_ value: RuleValue, against baseURL: String) -> [String] {
        let rawValues: [String]
        switch value {
        case .none: rawValues = []
        case let .string(value): rawValues = value.components(separatedBy: "\n")
        case let .strings(values): rawValues = values
        }
        var seen: Set<String> = []
        return rawValues.compactMap { raw -> String? in
            let resolved = resolveLegadoURL(raw, against: baseURL)
            guard !raw.isEmpty, !resolved.isEmpty, seen.insert(resolved).inserted else { return nil }
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
        let resolved = urlResolver.resolve(url, against: base)
        return "\(resolved),\(options)"
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

    private static func isTrue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "null" else { return false }
        return !["false", "no", "not", "0"].contains(trimmed.lowercased())
    }
}

private struct Page: Sendable {
    let requestURL: String
    let baseURL: String
    let redirectURL: String
    let response: HTTPResponse
}

private struct IndexedPage: Sendable {
    let index: Int
    let page: Page
}

private struct ParsedPage {
    let chapters: [ParsedChapter]
    let nextURLs: [String]
}

private struct ParsedChapter {
    let name: String
    let rawURL: String
    let resolvedURL: String
    let isVolume: Bool
    let isVIP: Bool
    let isPay: Bool
    let tag: String
}
